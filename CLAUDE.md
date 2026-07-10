# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design System

`DESIGN.md` is the source of truth for ClaudeMeter's SwiftUI visual system. When
changing SwiftUI views, widgets, menu bar UI, or Live Activities, consult it and
preserve its color, typography, spacing, material, icon, and status-system
rules.

## Build Commands

Multi-platform SwiftUI app (macOS + iOS) built with Xcode (no npm/yarn/package managers).

**Available schemes:**
- `ClaudeMeter` - macOS menu bar app
- `ClaudeMeter-iOS` - iOS app with Dashboard
- `ClaudeMeterWidgetsExtension` - iOS Widgets and Live Activities
- `ClaudeMeterKit` - Shared Swift Package (data models)

```bash
# Build macOS app
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug build

# Build iOS app (iPhone 17 Pro)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build iPadOS app (iPad Air 11-inch M3)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' build

# Build iOS widgets
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeterWidgetsExtension -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build for release (macOS)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build

# Run tests (macOS)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter test

# Run tests (iOS - iPhone 17 Pro)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run tests (iPadOS - iPad Air 11-inch M3)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' test
```

Or open `ClaudeMeter.xcodeproj` in Xcode: ⌘B to build, ⌘R to run.

## ClaudeMeterKit (Shared Package)

**Location:** `ClaudeMeterKit/` - Swift Package for cross-platform shared code

**Purpose:** Provides shared data models and utilities used across macOS app, iOS app, and widget extensions. Eliminates code duplication and ensures consistency.

**Platform Support:**
- macOS 15.0+
- iOS 18.0+

**Package Structure:**
```
ClaudeMeterKit/
├── Package.swift          # Swift Package manifest
├── Sources/ClaudeMeterKit/
│   └── Models/
│       └── UsageData.swift  # Shared usage models (UsageSnapshot, UsageWindow, etc.)
└── Tests/ClaudeMeterKitTests/
```

**Shared Models:**
| Model | Description |
|-------|-------------|
| `UsageSnapshot` | Complete usage data snapshot with session, opus, and optional sonnet windows |
| `UsageWindow` | Individual usage window with utilization %, reset time, and computed properties |
| `UsageWindowType` | Enum for window types (`.session`, `.opus`, `.sonnet`) with display names and durations |
| `UsageStatus` | Usage status enum (`.onTrack`, `.warning`, `.critical`) with colors and icons |

**Integration:** Imported via `import ClaudeMeterKit` in app targets, widgets, and extensions. Xcode automatically links the package.

## Architecture

MVVM with Swift Actors for thread safety. Multi-platform architecture with shared services and platform-specific UIs.

**macOS:**
```
ClaudeMeterApp (@main) + SwiftData ModelContainer
    ↓
MenuBarExtra + MainWindow (TabView: Dashboard, Settings, About)
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)  +  UpdaterController (@ObservableObject, @MainActor)
    ↓
MacOSCredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
    +  TokenUsageRepository (@ModelActor)  +  NotificationService (actor)
    +  LaunchAtLoginService  +  Sparkle
    ↓ (imports)
ClaudeMeterKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

**iOS:**
```
ClaudeMeter_iOSApp (@main)
    ↓
MainTabView (TabView: Dashboard, Settings, About)
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)
    ↓
iOSCredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
    +  LiveActivityManager  +  WidgetDataManager
    ↓ (imports)
ClaudeMeterKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

**Widgets:**
```
ClaudeMeterWidgetsBundle
    ↓
Home Screen Widgets (Small, Medium, Large) + Lock Screen Widget + Live Activity
    ↓
TimelineProvider  +  Shared WidgetDataManager
    ↓ (imports)
ClaudeMeterKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UsageViewModel` | ViewModels/ | State manager with auto-refresh via `Task`. Persists refresh interval to `UserDefaults`. |
| `MacOSCredentialService` | macOS/Services/ | Loads OAuth token from `~/.claude/.credentials.json`. Falls back to `NSOpenPanel` if sandboxed. |
| `iOSCredentialService` | iOS/Services/ | Loads OAuth token from `~/.claude/.credentials.json` via CredentialProvider + KeychainHelper. |
| `ClaudeAPIService` | Services/ | Fetches usage from Anthropic API. API constants in `Utilities/Constants.swift`. |
| `TokenUsageService` | Services/ | Scans local JSONL logs from `~/.claude/projects/` for token counts and calculates costs. Persists to SwiftData (macOS only). |
| `TokenUsageRepository` | Services/ | SwiftData `@ModelActor` for background queries of persisted token usage (macOS only). |
| `NotificationService` | Services/ | Threshold-based usage alerts (25%, 50%, 75%, 100%) with reset notifications (macOS only). |
| `UpdaterController` | Services/ | Sparkle updater integration for automatic updates. Observes `canCheckForUpdates` state (macOS only). |
| `LaunchAtLoginService` | macOS/Services/ | Manages Login Items for launching app on macOS startup (macOS 13+). |
| `LiveActivityManager` | iOS/Services/ | Manages Live Activities for Dynamic Island on iOS. |
| `WidgetDataManager` | Shared/Services/ | Provides usage data to widgets via App Groups for cross-process communication. |

### Data Models

**Shared Models (ClaudeMeterKit package):**

| Model | Purpose |
|-------|---------|
| `UsageSnapshot` | Contains `session`, `opus`, and optional `sonnet` usage windows + fetch timestamp |
| `UsageWindow` | Utilization %, reset time, window type. Computed: `normalized`, `status`, `timeUntilReset` |
| `UsageWindowType` | Enum: `.session`, `.opus`, `.sonnet` - with `displayName` and `totalDuration` |
| `UsageStatus` | Enum: `.onTrack`, `.warning`, `.critical` - calculated from usage rate with colors and icons |

**App-Specific Models:**

| Model | Purpose |
|-------|---------|
| `ClaudeOAuthCredentials` | Token validation + `planDisplayName` for UI |
| `TokenUsageSnapshot` | Contains `today`, `last30Days` summaries + `byModel` breakdown |
| `TokenUsageSummary` | Aggregated tokens + cost USD for a period (`.today` or `.last30Days`) |
| `TokenCount` | Input, output, cache creation, cache read token counts |
| `ModelPricing` | Per-model pricing rates (MTok): Opus 4.5, Sonnet 4.5, Sonnet 4, Haiku 4.5, Haiku 3.5 |
| `LiveActivityAttributes` | iOS Live Activity data model for Dynamic Island (iOS only) |

**SwiftData Persistence Models (macOS only):**

| Model | Purpose |
|-------|---------|
| `TokenLogEntry` | `@Model` - Persisted token usage entry from JSONL logs with unique composite ID |
| `ImportedFile` | `@Model` - Tracks imported JSONL files to prevent duplicates |

### API Response Mapping

| API Field | Model Field | Description |
|-----------|-------------|-------------|
| `five_hour` | `session` | 5-hour session window |
| `seven_day` | `opus` | Default weekly limit (Opus) |
| `seven_day_sonnet` | `sonnet` | Separate Sonnet limit (if available) |

### Patterns Used

- `@Observable` macro (Swift 5.9+) for reactive UI - no Combine
- `actor` for thread-safe services
- `@MainActor` on ViewModel for UI thread safety
- `@Environment` for dependency injection from App to Views
- `@Bindable` in SettingsView for two-way binding with @Observable
- `@Model` for SwiftData persistence (token usage, imported files)
- `@ModelActor` for background SwiftData queries without blocking main thread

### Data Persistence (macOS only)

**SwiftData Integration:**
- `ModelContainer` configured in `ClaudeMeterApp` for token usage persistence
- `@Model` classes: `TokenLogEntry` and `ImportedFile` for tracking parsed JSONL logs
- `@ModelActor` (`TokenUsageQuerier`) for non-blocking background queries
- Automatic deduplication via `@Attribute(.unique)` on composite ID
- Efficient aggregation queries for today/30-day summaries and by-model breakdowns

**Why macOS only:** Token usage data is read from `~/.claude/projects/` JSONL logs, which are only accessible on macOS where Claude Code runs. iOS app shows live API usage only.

### Coding Conventions

Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

## External Integration

- **API**: `https://api.anthropic.com/api/oauth/usage`
- **Auth**: Bearer token from `~/.claude/.credentials.json` (Claude CLI creates this)
- **API Config**: See `Utilities/Constants.swift` for URLs and beta header

### Local JSONL Logs

Token usage and costs are calculated from Claude Code's local JSONL logs:
- **Location**: `~/.claude/projects/` or `~/.config/claude/projects/`
- **Format**: One JSON object per line with `message.model`, `message.usage`, `timestamp`
- **Pricing**: Hardcoded rates based on [Anthropic pricing](https://anthropic.com/pricing)

## Platform Requirements

- **macOS**: 15.0 (Sequoia) or later
- **iOS**: 18.0 or later

## App Configuration

**macOS:**
- Menu bar only app: `LSUIElement = true` in Info.plist
- Sandbox disabled in entitlements (required for ~/.claude access)
- Network client entitlement enabled
- Sparkle auto-updates enabled: `SUEnableAutomaticChecks = true`

**iOS:**
- Live Activities support: `NSSupportsLiveActivities = true`
- Background modes: `remote-notification` for Live Activity updates
- App Groups for widget data sharing

## iOS Features

**Home Screen Widgets:**
- Small Widget: Single usage window (Session, Opus, or Sonnet)
- Medium Widget: Two usage windows side-by-side
- Large Widget: All usage windows + token usage summary

**Lock Screen Widget:**
- Compact gauge showing worst usage status across all windows

**Live Activity (Dynamic Island):**
- Real-time usage tracking in Dynamic Island and Lock Screen
- Updates automatically when app is active
- Managed via `LiveActivityManager` actor

**Widget Implementation:**
- Timeline-based updates via `TimelineProvider`
- Data sharing via `WidgetDataManager` and App Groups
- Supports widget configuration and sizing

## macOS Features

**Menu Bar:**
- Color-coded status icon (green/orange/red based on usage)
- Orange badge dot when update is available
- Countdown timer when at 100% usage
- Quick access popover with usage cards

**Notifications:**
- Threshold alerts at 25%, 50%, 75%, 100%
- Reset notifications when limit resets after being near capacity
- Per-window tracking to avoid duplicate notifications
- Test notification button in Settings

**Launch at Login:**
- Native macOS Login Items integration (macOS 13+)
- Managed via `LaunchAtLoginService`
- User-configurable in Settings

**Window Management:**
- Dynamic dock icon (shows when main window open, hides otherwise)
- TabView navigation: Dashboard, Settings, About
- Window opens via menu bar or keyboard shortcut (⌘,)

## Auto-Updates (Sparkle - macOS only)

The macOS app uses [Sparkle](https://sparkle-project.org/) framework for automatic updates:

- **UpdaterController**: Wrapper around `SPUStandardUpdaterController` for SwiftUI integration
- **Feed URL**: `https://tartinerlabs.github.io/ClaudeMeter/appcast.xml` (in Info.plist) — served from GitHub Pages off the `gh-pages` branch. Moved off `raw.githubusercontent.com`, which structurally rate-limited (HTTP 429) the constantly-polled feed. The feed is **accumulating**: each release prepends its `<item>` to the existing feed, so it carries the full version history (Sparkle shows past "What's New" notes).
- **Public Key**: EdDSA public key in Info.plist for signature verification
- **Check for Updates**: Manual check button in Settings view, disabled when update check is already in progress
- **Auto-check**: Sparkle automatically checks based on user preferences

### Versioning

Version is managed via `Config/Version.xcconfig` (single source of truth):

```xcconfig
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
```

- **MARKETING_VERSION**: User-facing version (X.Y.Z format, per Apple guidelines)
- **CURRENT_PROJECT_VERSION**: Build number (must always increase)

### Release Workflow

Releases use the manually triggered `.github/workflows/release.yml`; a normal push to `main` runs CI only. The default `dry-run` operation has read-only permissions. `publish` and `repair-appcast` require the `release` environment, `SIGNED_RELEASES_ENABLED=true`, and the relevant Developer ID, Apple notarization, and Sparkle secrets.

The publish path tests, computes or resumes the version, prepares the changelog, Developer ID-signs, notarizes, staples, packages, validates with Gatekeeper, generates the accumulating feed with Sparkle's official `generate_appcast`, commits the version with compare-and-swap protection, creates the tag/prerelease, publishes `appcast.xml` to `gh-pages`, and explicitly dispatches `pages.yml`.

Do not manually edit versions, tag, or call `gh release create`. Use:

```bash
gh workflow run release.yml -f operation=dry-run -f bump=auto
gh workflow run release.yml -f operation=publish -f bump=auto
gh workflow run release.yml -f operation=repair-appcast -f tag=vX.Y.Z
```

Public releases remain paused until Developer ID credentials are configured. The committed `0.26.0` build `79` is the next release candidate and is resumed regardless of the requested bump. See `RELEASING.md` and `.claude/skills/release/SKILL.md` for setup and recovery.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
