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
CredentialService (actor)  +  ClaudeAPIService (actor)  +  TokenUsageService (actor)
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UsageViewModel` | ViewModels/ | State manager with auto-refresh via `Task`. Persists refresh interval to `UserDefaults`. |
| `CredentialService` | Services/ | Loads OAuth token from `~/.claude/.credentials.json`. Falls back to `NSOpenPanel` if sandboxed. |
| `ClaudeAPIService` | Services/ | Fetches usage from Anthropic API. API constants in `Utilities/Constants.swift`. |
| `TokenUsageService` | Services/ | Scans local JSONL logs from `~/.claude/projects/` for token counts and calculates costs. |

### Data Models

| Model | Purpose |
|-------|---------|
| `UsageSnapshot` | Contains `session`, `opus`, and optional `sonnet` usage windows + fetch timestamp |
| `UsageWindow` | Utilization %, reset time, window type. Computed: `normalized`, `status`, `timeUntilReset` |
| `UsageWindowType` | Enum: `.session`, `.opus`, `.sonnet` |
| `UsageStatus` | Enum: `.onTrack`, `.warning`, `.critical` - calculated from usage rate |
| `ClaudeOAuthCredentials` | Token validation + `planDisplayName` for UI |
| `TokenUsageSnapshot` | Contains `today`, `last7Days` summaries + `byModel` breakdown |
| `TokenUsageSummary` | Aggregated tokens + cost USD for a period |
| `TokenCount` | Input, output, cache creation, cache read token counts |
| `ModelPricing` | Per-model pricing rates (MTok) from LiteLLM data |

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
- **Pricing**: Hardcoded rates from [LiteLLM pricing data](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)

## App Configuration

- Menu bar only app: `LSUIElement = true` in Info.plist
- Sandbox disabled in entitlements (required for ~/.claude access)
- Network client entitlement enabled
