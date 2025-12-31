# ClaudeMeter

A native macOS menu bar application that monitors your Claude API usage in real-time.

## Overview

ClaudeMeter is a lightweight menu bar app that displays your Claude Code API usage statistics directly in your macOS menu bar. It tracks both session (5-hour) and weekly (7-day) rate limits, helping you stay informed about your API consumption.

## Features

- **Real-time Usage Monitoring**: Track your Claude API usage with automatic refresh
- **Session & Weekly Limits**: Monitor both 5-hour session and 7-day weekly rate limits
- **Visual Indicators**: Color-coded usage levels (green, yellow, red) based on consumption
- **Countdown Timers**: See when your usage limits will reset
- **Auto-Refresh**: Configurable refresh intervals (1, 2, 5, or 15 minutes)
- **Native macOS**: Built with Swift and SwiftUI for optimal performance
- **Menu Bar Integration**: Lightweight app that lives in your menu bar

## Requirements

- macOS 14.0 (Sonoma) or later
- Claude CLI installed and authenticated
- Active Claude Code subscription

## Installation

### Prerequisites

1. Install Claude CLI:
   ```bash
   # Installation method depends on your package manager
   # Follow instructions at claude.ai/code
   ```

2. Authenticate with Claude:
   ```bash
   claude auth login
   ```
   This creates the credentials file at `~/.claude/.credentials.json` that ClaudeMeter uses.

### Building from Source

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd ClaudeMeter
   ```

2. Open in Xcode:
   ```bash
   open ClaudeMeter.xcodeproj
   ```

3. Build and run:
   - Press `⌘B` to build
   - Press `⌘R` to run

Or use command line:
```bash
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build
```

## Usage

1. Launch ClaudeMeter
2. The app appears in your menu bar with a chart icon
3. Click the icon to view your usage statistics:
   - **Session (5hr)**: Current 5-hour rolling window usage
   - **Weekly**: Current 7-day rolling window usage
   - Reset timers showing when limits refresh
4. Click **Settings** to configure auto-refresh interval
5. Click **Refresh** to manually update usage data

### Understanding Usage Indicators

- **Green** (0-49%): Healthy usage levels
- **Yellow** (50-79%): Moderate usage
- **Red** (80-100%): High usage, approaching limit

## Configuration

### Refresh Intervals

Choose from the Settings menu:
- Manual (refresh on demand)
- 1 minute
- 2 minutes
- 5 minutes (default)
- 15 minutes

### Credentials

ClaudeMeter reads OAuth credentials from `~/.claude/.credentials.json`. If this file is not found or you're running in a sandboxed environment, the app will prompt you to select the file manually.

## Architecture

Built using modern Swift patterns:
- **MVVM Architecture**: Clean separation of concerns
- **Swift Actors**: Thread-safe service operations
- **@Observable**: Modern reactive UI (Swift 5.9+)
- **Async/Await**: Modern concurrency patterns

## Troubleshooting

### "Credentials not found" error

1. Ensure Claude CLI is installed and authenticated:
   ```bash
   claude auth login
   ```

2. Verify credentials file exists:
   ```bash
   ls -la ~/.claude/.credentials.json
   ```

### "Unauthorized" error

Your credentials may have expired. Re-authenticate with Claude CLI:
```bash
claude auth login
```

### App not showing in menu bar

Check that the app is running (look in Activity Monitor for "ClaudeMeter"). If not visible, try restarting the app.

## Development

### Project Structure

```
ClaudeMeter/
├── ClaudeMeter/
│   ├── ClaudeMeterApp.swift       # App entry point
│   ├── Models/                    # Data models
│   ├── Services/                  # API and credential services
│   ├── ViewModels/                # State management
│   ├── Views/                     # SwiftUI views
│   └── Utilities/                 # Constants and helpers
├── ClaudeMeterTests/              # Unit tests
└── ClaudeMeterUITests/            # UI tests
```

### Building

```bash
# Debug build
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug build

# Release build
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Release build

# Run tests
xcodebuild -project ClaudeMeter.xcodeproj -scheme ClaudeMeter test
```

## Privacy & Security

- **No Data Collection**: ClaudeMeter does not collect or transmit any usage data
- **Local Credentials**: OAuth tokens are read from your local `~/.claude/.credentials.json` file
- **Secure API**: All API requests use HTTPS with Bearer token authentication
- **Sandbox**: App runs with minimal permissions (network access for API calls)

## Technical Details

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Minimum macOS**: 14.0 (Sonoma)
- **Architecture**: MVVM with Swift Actors
- **API**: Anthropic OAuth API (`https://api.anthropic.com/api/oauth/usage`)

## License

[Add your license information here]

## Contributing

[Add contribution guidelines if applicable]

## Support

For issues or questions:
- Check existing issues in the repository
- Review troubleshooting section above
- Create a new issue with detailed information

## Version

Current version: 1.0

---

Built with ❤️ for the Claude Code community
