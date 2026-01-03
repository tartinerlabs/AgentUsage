# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Multi-platform SwiftUI app (macOS + iOS) built with Xcode (no npm/yarn/package managers).

**Available schemes:**
- `ClaudeMeter` - macOS menu bar app
- `ClaudeMeter-iOS` - iOS app with Dashboard
- `ClaudeMeterWidgetsExtension` - iOS Widgets and Live Activities

```bash
# Build macOS app
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug build

# Build iOS app
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS -configuration Debug build

# Build iOS widgets
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeterWidgetsExtension -configuration Debug build

# Build for release (macOS)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build

# Run tests (macOS)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter test

# Run tests (iOS)
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter-iOS test
```

Or open `ClaudeMeter.xcodeproj` in Xcode: ⌘B to build, ⌘R to run.

## Architecture

MVVM with Swift Actors for thread safety. Multi-platform architecture with shared services and platform-specific UIs.

**macOS:**
```
ClaudeMeterApp (@main)
    ↓
MenuBarExtra + MainWindow (TabView: Dashboard, Settings, About)
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)  +  UpdaterController (@ObservableObject, @MainActor)
    ↓
MacOSCredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
    +  NotificationService (actor)  +  LaunchAtLoginService  +  Sparkle
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
```

**Widgets:**
```
ClaudeMeterWidgetsBundle
    ↓
Home Screen Widgets (Small, Medium, Large) + Lock Screen Widget + Live Activity
    ↓
TimelineProvider  +  Shared WidgetDataManager
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UsageViewModel` | ViewModels/ | State manager with auto-refresh via `Task`. Persists refresh interval to `UserDefaults`. |
| `MacOSCredentialService` | macOS/Services/ | Loads OAuth token from `~/.claude/.credentials.json`. Falls back to `NSOpenPanel` if sandboxed. |
| `iOSCredentialService` | iOS/Services/ | Loads OAuth token from `~/.claude/.credentials.json` via CredentialProvider + KeychainHelper. |
| `ClaudeAPIService` | Services/ | Fetches usage from Anthropic API. API constants in `Utilities/Constants.swift`. |
| `TokenUsageService` | Services/ | Scans local JSONL logs from `~/.claude/projects/` for token counts and calculates costs. |
| `NotificationService` | Services/ | Threshold-based usage alerts (25%, 50%, 75%, 100%) with reset notifications (macOS only). |
| `UpdaterController` | Services/ | Sparkle updater integration for automatic updates. Observes `canCheckForUpdates` state (macOS only). |
| `LaunchAtLoginService` | macOS/Services/ | Manages Login Items for launching app on macOS startup (macOS 13+). |
| `LiveActivityManager` | iOS/Services/ | Manages Live Activities for Dynamic Island on iOS. |
| `WidgetDataManager` | Shared/Services/ | Provides usage data to widgets via App Groups for cross-process communication. |

### Data Models

| Model | Purpose |
|-------|---------|
| `UsageSnapshot` | Contains `session`, `opus`, and optional `sonnet` usage windows + fetch timestamp |
| `UsageWindow` | Utilization %, reset time, window type. Computed: `normalized`, `status`, `timeUntilReset` |
| `UsageWindowType` | Enum: `.session`, `.opus`, `.sonnet` |
| `UsageStatus` | Enum: `.onTrack`, `.warning`, `.critical` - calculated from usage rate |
| `ClaudeOAuthCredentials` | Token validation + `planDisplayName` for UI |
| `TokenUsageSnapshot` | Contains `today`, `last30Days` summaries + `byModel` breakdown |
| `TokenUsageSummary` | Aggregated tokens + cost USD for a period (`.today` or `.last30Days`) |
| `TokenCount` | Input, output, cache creation, cache read token counts |
| `ModelPricing` | Per-model pricing rates (MTok): Opus 4.5, Sonnet 4.5, Sonnet 4, Haiku 4.5, Haiku 3.5 |
| `LiveActivityAttributes` | iOS Live Activity data model for Dynamic Island (iOS only) |

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
- **iOS**: 17.0 or later

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
- **Feed URL**: `https://raw.githubusercontent.com/tartinerlabs/ClaudeMeter/main/appcast.xml` (in Info.plist)
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

GitHub Actions automates releases via `.github/workflows/release.yml`:

1. **Trigger**: Publish a GitHub release
2. **Validate**: Ensures git tag matches `Config/Version.xcconfig` version
3. **Build**: Builds unsigned app, creates zip archive
4. **Sign**: Signs update with Sparkle EdDSA key
5. **Appcast**: Generates appcast.xml with version and signature
6. **Upload**: Attaches zip to GitHub release
7. **Commit**: Pushes updated appcast.xml back to main branch

**Creating a release:**

```bash
# 1. Update Config/Version.xcconfig
MARKETING_VERSION = 0.2.0
CURRENT_PROJECT_VERSION = 2

# 2. Update CHANGELOG.md with release notes

# 3. Commit
git add . && git commit -m "Bump version to 0.2.0"

# 4. Tag (must match xcconfig version)
git tag v0.2.0

# 5. Push
git push && git push --tags

# 6. Create release with detailed notes
gh release create v0.2.0 --title "ClaudeMeter 0.2.0" --notes-file - --prerelease <<'EOF'
## What's New

### Added
- Feature description here

### Fixed
- Bug fix description here

### Changed
- Change description here

See [CHANGELOG.md](CHANGELOG.md) for full details.
EOF
```

For stable releases (1.0.0+), omit `--prerelease` flag.
