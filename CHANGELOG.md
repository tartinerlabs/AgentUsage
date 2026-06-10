# Changelog

All notable changes to ClaudeMeter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.4] - 2026-06-10

- Sign release bot commits via the GitHub API

## [0.14.3] - 2026-06-10

- Trigger release after CI signing fix
- Document the usage endpoint URL constant
- Extract release logic into local composite actions
- Address PR review: abort on moved main, create release after signing, pin checkout SHA
- Automate releases on push to main

## [0.14.2] - 2026-06-10

### Changed
- Rebuilt and verified against Xcode 27 / macOS 27 (build and full test suite pass on the new SDK).

### Fixed
- Two environment-dependent test failures: `returnsNilForUnknownModel` raced the live LiteLLM pricing map (which now legitimately prices `gpt-4`) and asserts the static fallback instead; `initialStateIsCorrect` leaked the real app's cached usage snapshot from the shared UserDefaults domain and now stashes and restores it.

## [0.14.1] - 2026-06-10

### Fixed
- Use LiteLLM pricing data as the source of truth for token cost calculations, preferring a configured LiteLLM proxy's `/model/info` pricing and falling back to LiteLLM's hosted model cost map.
- Refresh LiteLLM pricing before local token imports, zero-cost recalculation, live provider aggregation, and blog usage sync so newly released models such as Claude Mythos/Fable 5 can be priced without hardcoded app updates.

## [0.14.0] - 2026-06-08

### Added
- Per-provider service outage detection. When a provider's usage fetch fails with an HTTP 5xx / service-unavailable error, ClaudeMeter now tracks an outage and shows a "Service down" indicator on that provider's card (menu bar popover) and a banner on its detail page (menu bar + Dashboard), while continuing to show cached data. Covers Claude, Codex, and OpenCode; the indicator clears automatically on the next successful fetch.

### Fixed
- OpenCode Go dashboard usage windows never parsed due to a malformed regex (raw-string delimiter bug), so OpenCode rate-limit windows were always missing. The parser now extracts rolling/weekly/monthly usage correctly.
- Manual refresh is no longer throttled — pressing refresh always fetches immediately (the 5-second cooldown only applied to forced refreshes and is removed).

## [0.13.5] - 2026-06-07

### Fixed
- Stop the remaining macOS keychain authorization prompt on launch, caused by blog usage sync reading its bearer token in-process. The token is now stored and read via the `/usr/bin/security` CLI — whose stable Apple-signed binary lets the keychain "Always Allow" grant persist — instead of in-process keychain APIs that re-prompt on every launch for the unsigned app. After updating, re-enter the blog sync token once in Settings.

## [0.13.4] - 2026-06-07

### Fixed
- Stop a recurring macOS keychain authorization prompt on launch. The app no longer writes a copy of the Claude credentials into its own keychain on every refresh — that write was unused (macOS reads the token directly from Claude Code via the `security` CLI, and iCloud sync is not enabled) and was the source of the repeated "ClaudeMeter wants to use your confidential information" dialog.

## [0.13.3] - 2026-06-07

### Fixed
- Codex 5-hour and weekly windows now read live usage from the ChatGPT backend (`/wham/usage`) using the `~/.codex/auth.json` token, instead of stale local rollout logs. Usage consumed via OpenCode/ChatGPT is now reflected, fixing the menu bar showing 0% when the local Codex CLI logs were stale. Falls back to hiding the Codex column on any error rather than showing a fabricated 0%.

## [0.13.2] - 2026-06-07

### Fixed
- Skip Claude Code `<synthetic>` placeholder rows during blog usage sync so zero-token internal messages are not stored as Anthropic model usage.

## [0.13.1] - 2026-06-07

### Removed
- Credentials status section from Settings (no longer needed).

## [0.13.0] - 2026-06-07

### Added
- Multi-provider usage monitoring (macOS): track **OpenAI Codex CLI** and **OpenCode** alongside Claude.
- Codex rate-limit windows (5-hour + weekly) and plan, read from local Codex rollout logs — no login required.
- Token usage & cost for Codex and OpenCode, computed from local logs (OpenCode via its SQLite database) using built-in pricing.
- OpenUsage-style menu-bar popover: a provider sidebar that switches between an overview and per-provider detail pages, each with Status/Console links, window status dots, Today/Yesterday/30-day cost, a usage-trend sparkline, and a per-model breakdown.
- Shared per-provider cards across the menu bar and Dashboard.
- "Codex (5h)" menu-bar display toggle in Settings.

## [0.12.2] - 2026-06-06

### Fixed
- Fix synced usage pricing
- Align blog usage sync contract

## [0.12.1] - 2026-06-06

### Changed
- Removed the ccusage backend; the native Claude JSONL parser is now the sole source of token usage and cost. Displayed totals are Claude-only and priced at Anthropic rates, fixing discrepancies caused by ccusage running unscoped across all coding agents with LiteLLM pricing.

## [0.12.0] - 2026-06-06

### Added
- Add passive blog usage sync for local agent usage.
- Add blog sync settings for endpoint URL, bearer token, manual sync, and sync status.

### Fixed
- Fix release metadata and Sparkle appcast release notes so updater notes render correctly.

## [0.11.0] - 2026-04-18

### Added
- Track Claude Design usage as a third weekly window (alongside All models and Sonnet)
- Show Claude Design in macOS menu bar icon, popover, and Dashboard; iOS Dashboard; and Medium/Large widgets
- Add `menuBarShowDesign` toggle in macOS Settings (Menu Bar Display)
- Add `notifyDesign` threshold notifications in macOS Settings (Notifications)
- Add Claude Design as a Live Activity metric on iOS

## [0.10.9] - 2026-03-18

### Fixed
- Add missing GITHUB_TOKEN for gh CLI in release workflow

## [0.10.8] - 2026-03-18

### Fixed
- Fix release workflow failing on asset upload by replacing softprops/action-gh-release with gh CLI

## [0.10.7] - 2026-03-18

### Fixed
- Fix repeated keychain access prompts on every launch by using security CLI instead of SecItemCopyMatching
- Remove obsolete file-based credential fallback (credentials file no longer exists in newer Claude Code)

### Changed
- Use update-or-add pattern in KeychainHelper to avoid unnecessary delete-then-add churn

## [0.10.6] - 2026-03-14

### Fixed
- Fix 1-second timers running continuously in MenuBarView, DashboardTabView, and MenuBarIconView (reduced to 60s)
- Fix stale countdown in menu bar icon when usage drops below 100%
- Fix period selector not fetching data when selection changes in Dashboard
- Fix fallback period label showing hardcoded "30 Days" regardless of selected period
- Fix NotificationSettings loading from UserDefaults on every toggle interaction
- Fix menu bar icon render failure producing silent empty image

### Changed
- Make API service injectable in UsageViewModel for improved testability

## [0.10.5] - 2026-02-08

### Fixed
- Fix repeating credential file dialog appearing on every auto-refresh cycle when credentials are missing

## [0.10.4] - 2026-02-08

### Fixed
- Fix credential loading after Claude Code moved from file to macOS Keychain

## [0.10.3] - 2026-02-08

### Fixed
- Fix Opus 4.6 token usage and costs showing as $0 (add pricing support for new model)

## [0.10.2] - 2026-02-07

### Added
- Display app version in menu bar popover footer

### Changed
- Allow multiple app instances to run simultaneously (reverted single-instance enforcement)

## [0.10.1] - 2026-02-07

### Fixed
- Prevent multiple app instances from running simultaneously (activates existing instance)

## [0.10.0] - 2026-02-07

### Added
- Extra usage tracking for paid accounts (cache creation and extra input tokens)
- New settings to control extra usage indicators and notifications
- Account requirement hint for extra usage feature (requires paid plan with OAuth)

### Changed
- Extra usage cost display now uses dusty plum color for better visual distinction
- CMD+Q now quits the app completely (restored standard macOS behavior)

## [0.9.3] - 2026-02-06

### Fixed
- CMD+Q now closes main window instead of quitting app, keeping menu bar alive

## [0.9.2] - 2026-02-06

### Fixed
- Fix token usage and costs not updating in background when offline or between API refreshes

## [0.9.1] - 2026-01-30

### Fixed
- Fix background refresh not starting on app launch (broke in 0.9.0 refactor)

## [0.9.0] - 2026-01-29

### Added
- Service protocols for dependency injection and improved testability
- DependencyContainer for centralized service creation
- TokenRefreshService for automatic OAuth token refresh
- Shared utilities in ClaudeMeterKit (DateFormatters, UsageCalculations, WidgetDataStorage)
- Mock implementations for unit testing (MockAPIService, MockCredentialProvider, MockNotificationService)
- Comprehensive unit tests for utilities and edge cases (16+ new tests)
- Human-readable keychain error messages for better debugging

### Changed
- Refactor architecture with protocol-based services
- Consolidate duplicated code into ClaudeMeterKit package
- Extract RefreshScheduler and MenuBarSettingsManager from UsageViewModel
- Unified WidgetDataManager between app and widget extension

### Fixed
- TokenUsageService now continues processing when individual JSONL files fail (partial success)
- Improved error handling with descriptive keychain status messages

## [0.8.3] - 2026-01-23

### Fixed
- Fix Sparkle auto-update not triggering background checks for menu bar apps
- Add comprehensive logging for update check debugging (viewable in Console.app)
- Add "Last Checked" display in Settings to verify update checks are occurring
- Schedule automatic background check 30 seconds after app launch

### Added
- Debug tool to force background update check (DEBUG builds only)

## [0.8.2] - 2026-01-12

### Fixed
- Fix false usage reset notifications when at 90%+ capacity

## [0.8.1] - 2026-01-12

### Fixed
- Fix "Check Now" button disappearing after update check (now stays visible with result text)
- Fix update check results not auto-dismissing for all result types
- Fix initial canCheckForUpdates state not syncing on app launch

### Changed
- Increase automatic update check frequency from 24 hours to 4 hours

## [0.8.0] - 2026-01-12

### Changed
- Redesign menu bar display with multi-line layout showing labels above percentages
- Add labels (CURR, ALL, SONNET) for better usage window identification
- Improve rendering with Retina display support via ImageRenderer

## [0.7.1] - 2026-01-10

### Fixed
- Token usage errors now display to users instead of failing silently

## [0.7.0] - 2026-01-05

### Added
- Token usage persistence with SwiftData for faster startup and historical tracking (macOS)
- ClaudeMeterKit Swift Package for shared models across macOS, iOS, and widgets

### Changed
- Bump iOS deployment target to iOS 18.0
- Refactor usage data models into shared ClaudeMeterKit package

### Fixed
- Pin GitHub Action to commit hash for improved CI security

## [0.6.3] - 2026-01-04

### Changed
- Style subscription tier as brand badge for better visual distinction
- Update labels and fonts to follow Apple Human Interface Guidelines

### Fixed
- Fix Check for Updates button state not updating correctly

## [0.6.2] - 2026-01-04

### Fixed
- Fix markdown links not rendering as clickable in Sparkle update dialog

## [0.6.1] - 2026-01-04

### Fixed
- Enable automatic update checks by default for menu bar app (fixes update prompts not appearing)

## [0.6.0] - 2026-01-04

### Added
- Launch at Login option in Settings to start ClaudeMeter automatically on login

### Changed
- Load usage stats immediately on app launch instead of waiting for menu bar click
- Improved update checking with better feedback UI and state management

## [0.5.2] - 2026-01-04

### Added
- Countdown timer in menu bar when usage reaches 100%
- Reset notifications when usage window resets after being near/at limit
- Keyboard shortcut tooltips on menu bar action buttons (Refresh, Settings, Quit)

### Changed
- Menu bar now shows time remaining until reset when at capacity

## [0.5.1] - 2026-01-04

### Fixed
- Restore Liquid Glass effect in release builds by updating CI runner to macOS 26

## [0.5.0] - 2026-01-04

### Added
- Usage threshold notifications with customizable alert levels
- Test notification button in Settings for verifying notification permissions
- Visual progress bar dividers at 25%, 50%, 75% markers

### Changed
- Updated deployment targets to macOS 15 and iOS 17

## [0.4.0] - 2026-01-03

### Added
- Popover menu with quick access to Settings, About, and Quit
- Dynamic dock icon behavior (shows when main window is open, hides otherwise)
- TabView navigation for iOS and macOS platforms

### Changed
- Improved Settings and About tab layouts with better visual hierarchy
- Added hover effect to menu items for better interactivity
- Main window no longer shows on launch (menu bar-first experience)

## [0.3.0] - 2026-01-03

### Added
- Gentle reminders for Sparkle updates in menu bar apps
  - Orange badge dot on menu bar icon when update available
  - "Update Available" banner in popover with View button
  - System notification posted when scheduled update is found
  - State resets when user engages with update or session ends

## [0.2.3] - 2026-01-03

### Fixed
- Fix invalid code signature in release builds preventing Sparkle updates

## [0.2.2] - 2026-01-03

### Fixed
- Fix Sparkle update dialog showing raw GitHub page instead of formatted release notes

## [0.2.1] - 2026-01-03

### Fixed
- Fix Sparkle signature validation for auto-updates

## [0.2.0] - 2026-01-03

### Added
- Colored status bar icon that dynamically changes based on usage status
  - Green: On track (usage < 75% and within expected pace)
  - Orange: Warning (usage 75-89% or moderately ahead of pace)
  - Red: Critical (usage ≥ 90% or significantly ahead of pace)
- Icon displays worst status across all usage windows for at-a-glance monitoring

### Changed
- Improved status calculation to check absolute usage levels in addition to consumption rate
- Status thresholds now prioritize high absolute usage (≥90% always critical, ≥75% always warning)

## [0.1.1] - 2026-01-03

### Fixed
- Fix token usage and cost calculation being ~2.8x higher than actual
- Add deduplication of streaming response entries by message.id + requestId (matching ccusage behavior)

## [0.1.0] - 2026-01-02

### Added
- macOS menu bar app displaying Claude Code usage limits
- Session (5-hour) and weekly (7-day) usage windows with visual progress bars
- Opus and Sonnet usage tracking with separate indicators
- Reset time countdown showing when limits refresh
- Auto-refresh with configurable intervals (1, 5, 15, 30 minutes)
- Settings window for refresh interval configuration
- About window with app information
- Automatic updates via Sparkle framework
- Token usage tracking from local Claude Code JSONL logs
- Cost calculation based on model pricing (Opus, Sonnet, Haiku)
- iOS app with widget support (in development)
- Live Activity for Dynamic Island on iOS

### Technical
- MVVM architecture with Swift Actors for thread safety
- OAuth token authentication from `~/.claude/.credentials.json`
- xcconfig-based versioning with GitHub Actions automation

[Unreleased]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.14.4...HEAD
[0.14.4]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.14.3...v0.14.4
[0.14.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.14.2...v0.14.3
[0.14.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.14.1...v0.14.2
[0.14.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.5...v0.14.0
[0.13.5]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.4...v0.13.5
[0.13.4]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.3...v0.13.4
[0.13.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.2...v0.13.3
[0.13.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.1...v0.13.2
[0.13.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.12.2...v0.13.0
[0.12.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.12.1...v0.12.2
[0.12.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.9...v0.11.0
[0.10.9]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.8...v0.10.9
[0.10.8]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.7...v0.10.8
[0.10.7]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.6...v0.10.7
[0.10.6]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.5...v0.10.6
[0.10.5]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.4...v0.10.5
[0.10.4]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.9.3...v0.10.0
[0.9.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.6.3...v0.7.0
[0.6.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tartinerlabs/ClaudeMeter/releases/tag/v0.1.0
