# Changelog

All notable changes to ClaudeMeter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.10.2...HEAD
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
