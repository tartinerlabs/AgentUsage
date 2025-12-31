# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Native macOS SwiftUI app built with Xcode (no npm/yarn/package managers).

```bash
# Build from command line
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug build

# Build for release
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build

# Run tests
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter test
```

Or open `ClaudeMeter.xcodeproj` in Xcode: ⌘B to build, ⌘R to run.

## Architecture

MVVM with Swift Actors for thread safety.

```
ClaudeMeterApp (@main)
    ↓
MenuBarExtra + Settings Scene
    ↓ (.environment injection)
UsageViewModel (@Observable, @MainActor)
    ↓
CredentialService (actor)  +  ClaudeAPIService (actor)
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UsageViewModel` | ViewModels/ | State manager with auto-refresh via `Task`. Persists refresh interval to `UserDefaults`. |
| `CredentialService` | Services/ | Loads OAuth token from `~/.claude/.credentials.json`. Falls back to `NSOpenPanel` if sandboxed. |
| `ClaudeAPIService` | Services/ | Fetches usage from Anthropic API. API constants in `Utilities/Constants.swift`. |

### Data Models

| Model | Purpose |
|-------|---------|
| `UsageSnapshot` | Contains session (5-hour) and weekly (7-day) `UsageWindow` + fetch timestamp |
| `UsageWindow` | Utilization % (0-100) + reset time. Computed: `normalized` (0-1), `color` (green/yellow/red thresholds) |
| `ClaudeOAuthCredentials` | Token validation: checks expiry and `user:profile` scope |

### Patterns Used

- `@Observable` macro (Swift 5.9+) for reactive UI - no Combine
- `actor` for thread-safe services
- `@MainActor` on ViewModel for UI thread safety
- `@Environment` for dependency injection from App to Views
- `@Bindable` in SettingsView for two-way binding with @Observable

## External Integration

- **API**: `https://api.anthropic.com/api/oauth/usage`
- **Auth**: Bearer token from `~/.claude/.credentials.json` (Claude CLI creates this)
- **API Config**: See `Utilities/Constants.swift` for URLs and beta header

## App Configuration

- Menu bar only app: `LSUIElement = true` in Info.plist
- Sandbox disabled in entitlements (required for ~/.claude access)
- Network client entitlement enabled
