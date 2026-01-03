# Changelog

All notable changes to ClaudeMeter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/tartinerlabs/ClaudeMeter/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tartinerlabs/ClaudeMeter/releases/tag/v0.1.0
