# ClaudeMeter

A multi-platform app (macOS + iOS) that monitors your Claude Code API usage in real-time.

## Overview

Multi-platform app that monitors Claude Code API usage in real-time. Tracks session (5-hour) and weekly (7-day) rate limits for Opus and Sonnet models, plus token usage and cost from local logs.

**Platforms:**
- **macOS 15+**: Menu bar app with notifications and auto-updates
- **iOS 18+**: Dashboard app with widgets and Live Activity

## Features

**Core (macOS & iOS):**
- Real-time usage monitoring with auto-refresh (1, 2, 5, or 15 min intervals)
- Session (5hr) and weekly (7-day) rate limits for Opus and Sonnet
- Token usage tracking with cost calculation (today and last 30 days)
- Color-coded indicators (green/orange/red) and countdown timers
- Native Swift/SwiftUI with Claude brand colors

**macOS Only:**
- Menu bar app with dynamic color-coded icon
- Threshold notifications (25%, 50%, 75%, 100%) and reset alerts
- Launch at login option
- Auto-updates via Sparkle
- Orange badge when update available
- Keyboard shortcuts (⌘, for Settings)

**iOS Only:**
- Home Screen widgets (Small, Medium, Large)
- Lock Screen widget
- Live Activity for Dynamic Island
- Full dashboard app with tabs

## Requirements

- **macOS**: 15.0+ (Sequoia), Claude CLI authenticated
- **iOS**: 18.0+, iPhone with Dynamic Island (for Live Activity)
- Active Claude Code subscription

## Installation

**macOS:**
1. Download `ClaudeMeter.zip` from [Releases](https://github.com/tartinerlabs/ClaudeMeter/releases)
2. Move `ClaudeMeter.app` to Applications
3. Launch - appears in menu bar

**iOS:** Currently in development. Build from source (see below).

**Prerequisites:**
```bash
# Install and authenticate Claude CLI (creates ~/.claude/.credentials.json)
claude auth login
```

**Building from Source:**
```bash
git clone https://github.com/tartinerlabs/ClaudeMeter.git
cd ClaudeMeter
open ClaudeMeter.xcodeproj
# Select scheme: ClaudeMeter (macOS), ClaudeMeter-iOS, or ClaudeMeterWidgetsExtension
# Press ⌘B to build, ⌘R to run

# Or via command line:
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build
```

## Usage

**macOS:**
- Click menu bar icon to view Session (5hr), Opus, and Sonnet usage with reset timers
- Icon color indicates status: Green (on track), Orange (75-89%), Red (≥90%)
- Access Refresh, Settings (⌘,), About, and Quit from menu

**iOS:**
- Dashboard tab shows usage stats
- Add widgets: Long-press Home Screen → "+" → "ClaudeMeter"
- Lock Screen widget: Customize Lock Screen → widget area

**Token Usage:**
- Analyzes local JSONL logs (`~/.claude/projects/`) for token counts and costs
- Tracks input, output, cache creation/read tokens for all Claude models
- Shows today and last 30 days usage with Anthropic pricing
- All processing is local

## Configuration

**Settings (macOS - ⌘,):**
- **Refresh**: Manual, 1, 2, 5 (default), or 15 minutes
- **Notifications**: Threshold alerts (25%, 50%, 75%, 100%) and reset notifications
- **Launch at Login**: Auto-start on macOS startup
- **Updates**: Manual check or automatic background checks (orange badge when available)

**Settings (iOS):**
- Refresh intervals and version info via Settings tab

**Credentials:**
- Reads `~/.claude/.credentials.json` for API access
- Token usage from `~/.claude/projects/` JSONL logs
- Manual file selection if not found

## Architecture

MVVM with Swift Actors for thread safety, @Observable for reactive UI, and async/await concurrency.

## Troubleshooting

**Credentials not found:** Run `claude auth login` to authenticate

**Unauthorized error:** Re-authenticate with `claude auth login`

**App not in menu bar:** Check Activity Monitor for "ClaudeMeter" and restart if needed

**Token usage zero:** Verify logs exist at `~/.claude/projects/` (created when using Claude Code)

## Development

**Structure:** ClaudeMeter/ (macOS), ClaudeMeter-iOS/, ClaudeMeterWidgets/, ClaudeMeterKit/ (shared package), with Models, Services, ViewModels, Views

**Usage parity diff (ClaudeMeter vs ccusage):**
```bash
# Rolling last 30 days in system timezone
swift scripts/compare_usage.swift --last-30d --output ./usage-comparison

# Custom absolute range
swift scripts/compare_usage.swift \
  --start 2026-01-19T00:00:00-08:00 \
  --end 2026-02-18T23:59:59-08:00 \
  --tz America/Los_Angeles \
  --output ./usage-comparison
```

Artifacts:
- `usage-comparison/comparison-summary.json`: metadata, totals, per-model deltas, mismatch flag
- `usage-comparison/comparison-diagnostics.json`: dedup/boundary/model-mapping diagnostics
- `usage-comparison/comparison-table.md`: readable totals + per-model table

**Build:**
```bash
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter test
```

## Privacy & Security

No data collection or transmission. All processing is local. Reads credentials from `~/.claude/.credentials.json`. HTTPS API requests only. Sandbox disabled for `~/.claude/` access.

## Technical Details

**Stack:** Swift/SwiftUI, macOS 15+, iOS 18+, MVVM + Actors

**Updates:** [Sparkle 2.8.1](https://sparkle-project.org/) (macOS)

**Data:** Anthropic OAuth API for rate limits, local JSONL logs for tokens, [Anthropic pricing](https://anthropic.com/pricing)

**Releases:** Automated via GitHub Actions. See [releases](https://github.com/tartinerlabs/ClaudeMeter/releases).

## Support

Issues or questions? Check [existing issues](https://github.com/tartinerlabs/ClaudeMeter/issues) or troubleshooting above, then create a new issue.

**Releases:** https://github.com/tartinerlabs/ClaudeMeter/releases
