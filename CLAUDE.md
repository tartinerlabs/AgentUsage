# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design System

`DESIGN.md` is the source of truth for AgentUsage's SwiftUI visual system. When
changing SwiftUI views, widgets, menu bar UI, or Live Activities, consult it and
preserve its color, typography, spacing, material, icon, and status-system
rules.

## Build Commands

Multi-platform SwiftUI app (macOS + iOS) built with Xcode (no npm/yarn/package managers).

**Available schemes:**

- `AgentUsage` - multiplatform macOS menu bar and iOS/iPadOS dashboard app
- `AgentUsageWidgetsExtension` - iOS Widgets and Live Activities
- `AgentUsageKit` - Shared Swift Package (data models)

```bash
# Build macOS app
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug build

# Build iOS app (iPhone 17 Pro)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build iPadOS app (iPad Air 11-inch M3)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' build

# Build iOS widgets
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageWidgetsExtension -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build for release (macOS)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Release build

# Run tests (macOS)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage test

# Run tests (iOS - iPhone 17 Pro)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run tests (iPadOS - iPad Air 11-inch M3)
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' test
```

Or open `AgentUsage.xcodeproj` in Xcode: ⌘B to build, ⌘R to run.

## AgentUsageKit (Shared Package)

**Location:** `AgentUsageKit/` - Swift Package for cross-platform shared code

**Purpose:** Provides shared data models and utilities used across macOS app, iOS app, and widget extensions. Eliminates code duplication and ensures consistency.

**Platform Support:**

- macOS 15.0+
- iOS 18.0+

**Package Structure:**

```
AgentUsageKit/
├── Package.swift          # Swift Package manifest
├── Sources/AgentUsageKit/
│   └── Models/
│       └── UsageData.swift  # Shared usage models (UsageSnapshot, UsageWindow, etc.)
└── Tests/AgentUsageKitTests/
```

**Shared Models:**
| Model | Description |
|-------|-------------|
| `UsageSnapshot` | Complete usage data snapshot with session, opus, and optional sonnet windows |
| `UsageWindow` | Individual usage window with utilization %, reset time, and computed properties |
| `UsageWindowType` | Enum for window types (`.session`, `.opus`, `.sonnet`) with display names and durations |
| `UsageStatus` | Usage status enum (`.onTrack`, `.warning`, `.critical`) with colors and icons |

**Integration:** Imported via `import AgentUsageKit` in app targets, widgets, and extensions. Xcode automatically links the package.

## Architecture

MVVM with Swift Actors for thread safety. Multi-platform architecture with shared services and platform-specific UIs.

**macOS:**

```
AgentUsageApp (@main) + SwiftData ModelContainer
    ↓
MenuBarExtra + MainWindow (TabView: Dashboard, Settings, About)
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)  +  UpdaterController (@ObservableObject, @MainActor)
    ↓
MacOSCredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
    +  TokenUsageRepository (@ModelActor)  +  NotificationService (actor)
    +  LaunchAtLoginService  +  Sparkle
    ↓ (imports)
AgentUsageKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

**iOS:**

```
AgentUsage_iOSApp (@main)
    ↓
MainTabView (TabView: Dashboard, Settings, About)
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)
    ↓
iOSCredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
    +  LiveActivityManager  +  WidgetDataManager
    ↓ (imports)
AgentUsageKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

**Widgets:**

```
AgentUsageWidgetsBundle
    ↓
Home Screen Widgets (Small, Medium, Large) + Lock Screen Widget + Live Activity
    ↓
TimelineProvider  +  Shared WidgetDataManager
    ↓ (imports)
AgentUsageKit (Swift Package) - UsageSnapshot, UsageWindow, UsageStatus, etc.
```

### Key Components

| Component                    | Location         | Purpose                                                                                                                                                                                                                                                 |
| ---------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `UsageViewModel`             | ViewModels/      | State manager with auto-refresh via `Task`. Persists refresh interval to `UserDefaults`.                                                                                                                                                                |
| `MacOSCredentialService`     | macOS/Services/  | Loads the OAuth token from Claude Code's Keychain entry (with the app's own Keychain as fallback). Not filesystem-based, so it is unaffected by the App Sandbox.                                                                                        |
| `SandboxFolderAccessService` | macOS/Services/  | Grants the sandboxed app read access to the CLI log directories (`~/.claude`, `~/.codex`, `~/.local/share/opencode`) via user-selected folders and persisted security-scoped bookmarks. Access is resolved at launch and held for the process lifetime. |
| `iOSCredentialService`       | iOS/Services/    | Loads OAuth token from `~/.claude/.credentials.json` via CredentialProvider + KeychainHelper.                                                                                                                                                           |
| `ClaudeAPIService`           | Services/        | Fetches usage from Anthropic API. API constants in `Utilities/Constants.swift`.                                                                                                                                                                         |
| `TokenUsageService`          | Services/        | Scans local JSONL logs from `~/.claude/projects/` for token counts and calculates costs. Persists to SwiftData (macOS only).                                                                                                                            |
| `TokenUsageRepository`       | Services/        | SwiftData `@ModelActor` for background queries of persisted token usage (macOS only).                                                                                                                                                                   |
| `NotificationService`        | Services/        | Threshold-based usage alerts (25%, 50%, 75%, 100%) with reset notifications (macOS only).                                                                                                                                                               |
| `UpdaterController`          | Services/        | Sparkle updater integration for automatic updates. Observes `canCheckForUpdates` state (macOS only).                                                                                                                                                    |
| `LaunchAtLoginService`       | macOS/Services/  | Manages Login Items for launching app on macOS startup (macOS 13+).                                                                                                                                                                                     |
| `LiveActivityManager`        | iOS/Services/    | Manages Live Activities for Dynamic Island on iOS.                                                                                                                                                                                                      |
| `WidgetDataManager`          | Shared/Services/ | Provides usage data to widgets via App Groups for cross-process communication.                                                                                                                                                                          |

### Data Models

**Shared Models (AgentUsageKit package):**

| Model             | Purpose                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `UsageSnapshot`   | Contains `session`, `opus`, and optional `sonnet` usage windows + fetch timestamp            |
| `UsageWindow`     | Utilization %, reset time, window type. Computed: `normalized`, `status`, `timeUntilReset`   |
| `UsageWindowType` | Enum: `.session`, `.opus`, `.sonnet` - with `displayName` and `totalDuration`                |
| `UsageStatus`     | Enum: `.onTrack`, `.warning`, `.critical` - calculated from usage rate with colors and icons |

**App-Specific Models:**

| Model                    | Purpose                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `ClaudeOAuthCredentials` | Token validation + `planDisplayName` for UI                                          |
| `TokenUsageSnapshot`     | Contains `today`, `last30Days` summaries + `byModel` breakdown                       |
| `TokenUsageSummary`      | Aggregated tokens + cost USD for a period (`.today` or `.last30Days`)                |
| `TokenCount`             | Input, output, cache creation, cache read token counts                               |
| `ModelPricing`           | Per-model pricing rates (MTok): Opus 4.5, Sonnet 4.5, Sonnet 4, Haiku 4.5, Haiku 3.5 |
| `LiveActivityAttributes` | iOS Live Activity data model for Dynamic Island (iOS only)                           |

**SwiftData Persistence Models (macOS only):**

| Model           | Purpose                                                                         |
| --------------- | ------------------------------------------------------------------------------- |
| `TokenLogEntry` | `@Model` - Persisted token usage entry from JSONL logs with unique composite ID |
| `ImportedFile`  | `@Model` - Tracks imported JSONL files to prevent duplicates                    |

### API Response Mapping

| API Field          | Model Field | Description                          |
| ------------------ | ----------- | ------------------------------------ |
| `five_hour`        | `session`   | 5-hour session window                |
| `seven_day`        | `opus`      | Default weekly limit (Opus)          |
| `seven_day_sonnet` | `sonnet`    | Separate Sonnet limit (if available) |

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

- `ModelContainer` configured in `AgentUsageApp` for token usage persistence
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
- **App Sandbox enabled** (`ENABLE_APP_SANDBOX = YES`) for Mac App Store / TestFlight distribution. macOS uses its own `AgentUsage/AgentUsage.entitlements` (wired via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`), which keeps the app-group and adds `com.apple.security.files.user-selected.read-only`. Reading the CLI tools' log directories requires the user to grant folder access (Settings → Local Data Access); see `SandboxFolderAccessService`. Credentials come from the Keychain and need no folder grant.
- Network client entitlement enabled
- App Group `group.com.tartinerlabs.AgentUsage` backs the SwiftData store (pinned explicitly via `ModelConfiguration(groupContainer:)`) and widget data sharing
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
- **Feed URL**: `https://tartinerlabs.github.io/AgentUsage/appcast.xml` (in Info.plist) — served from GitHub Pages off the `gh-pages` branch. Moved off `raw.githubusercontent.com`, which structurally rate-limited (HTTP 429) the constantly-polled feed. The feed is **accumulating**: each release prepends its `<item>` to the existing feed, so it carries the full version history (Sparkle shows past "What's New" notes).
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

`Config/Version.xcconfig` is wired as the **project-level base configuration** (Debug and Release) in `AgentUsage.xcodeproj`, so all targets inherit these values — no target defines `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` inline. Edit the xcconfig only; the release workflow (`compute-version.sh` / `bump-version`) reads and rewrites it. Do not re-add these keys to per-target build settings, or they will override the xcconfig.

### Release Workflow

Releases use the manually triggered `.github/workflows/release.yml`; a normal push to `main` runs CI only. The default `dry-run` operation has read-only permissions and builds a fully validated ad-hoc-signed archive. Publishing always uses the protected `release` environment and requires the Sparkle private key.

`publish` is the Developer ID path and requires `SIGNED_RELEASES_ENABLED=true` plus the Apple signing and notarization secrets; it signs with Developer ID, notarizes, and staples. `publish-unsigned` is the ad-hoc fallback: it requires `UNSIGNED_RELEASES_ENABLED=true`, creates an ad-hoc code signature, and does not use Apple notarization. Both paths test, compute or resume the version, prepare the changelog, generate and verify the accumulating feed with Sparkle's official `generate_appcast`, commit with compare-and-swap protection, create the tag/prerelease, publish `appcast.xml` to `gh-pages`, and dispatch `pages.yml`.

Do not manually edit versions, tag, or call `gh release create`. Use:

```bash
gh workflow run release.yml -f operation=dry-run -f bump=auto
gh workflow run release.yml -f operation=publish-unsigned -f bump=auto
gh workflow run release.yml -f operation=publish -f bump=auto
gh workflow run release.yml -f operation=repair-appcast -f tag=vX.Y.Z
```

Signed, notarized Developer ID releases (`publish`) are the primary distribution mode, gated on `SIGNED_RELEASES_ENABLED=true` plus the Apple signing and notarization secrets in the `release` environment; `publish-unsigned` remains an ad-hoc fallback. An untagged version committed in `Config/Version.xcconfig` is resumed regardless of the requested bump. See `RELEASING.md` and `.claude/skills/release/SKILL.md` for setup, Gatekeeper behaviour, and recovery.
