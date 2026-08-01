# CLAUDE.md

Guidance for Claude Code working in this repository. This file covers what you
cannot infer by reading the code — everything else, read the code.

AgentUsage is a multi-platform SwiftUI app (macOS menu bar + iOS/iPadOS
dashboard + widgets) that monitors usage across several AI coding CLIs.

## Design system

`DESIGN.md` is the source of truth for the SwiftUI visual system. Consult it
before changing views, widgets, menu bar UI, or Live Activities. Note that the
palette lives in `Utilities/Constants.swift`, not `Assets.xcassets`.

## Build

`AgentUsage` is one destination-aware scheme for macOS, iOS, and iPadOS.
The simulator destination strings that are actually used:

```bash
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug build
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage test

xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' build
```

## Multi-provider architecture

The app is not Claude-only. Usage is collected per provider through two seams:

- `AgentUsageKit/Sources/AgentUsageKit/Models/Provider.swift` — `Provider` enum
  (`claude`, `codex`, `openCode`, `openCodeGo`, `cursor`). Each carries a `Capability` set
  (`.rateWindows` for live quota windows, `.tokenCost` for token/cost from local
  logs), a `pricingProviderKey` ("anthropic" / "openai"), and a `family` rollup.
  Check capabilities before assuming a provider surfaces a given kind of data.
- `AgentUsage/Shared/Protocols/UsageLogSource.swift` — `protocol UsageLogSource: Actor`,
  which normalizes each CLI's local logs into `ProviderUsageEntry` (provider,
  model, tokens, `dedupKey`, optional `precomputedCostUSD`, `fastMode`).
- `AgentUsage/Shared/Protocols/APIServiceProtocol.swift:24` —
  `ProviderUsageServiceProtocol` for live quota snapshots fetched from a provider's API.
- `AgentUsage/DependencyContainer.swift` wires the concrete implementations.
  Start here when adding a provider.

Two subsystems that are easy to miss: blog usage
(`Services/BlogOAuthService.swift`, `Services/BlogUsage/`, PKCE + RFC-8707 config
in `Constants.BlogOAuth`) and provider outage tracking (`OutageIncident`).

## Gotchas

These are non-obvious and have caused wrong changes before.

**OpenCode is deliberately disabled.** `DependencyContainer.swift:46` and `:87`
have `OpenCodeLogSource()` and `.openCodeGo: OpenCodeGoLocalUsageService()`
commented out — "OpenCode usage is currently unreliable". Tests exist for code
paths the app does not wire up. Uncommenting these reverts a deliberate
decision; don't do it to make a provider "work".

**Credentials come from the Keychain, not the filesystem.**
`macOS/Services/MacOSCredentialService.swift` shells out to `/usr/bin/security`
to read Claude Code's Keychain entry, which is why the App Sandbox doesn't block
it and why no folder grant is needed for auth.

**Reading CLI logs does need a folder grant.**
`macOS/Services/SandboxFolderAccessService.swift` resolves security-scoped
bookmarks for `~/.claude`, `~/.codex`, and `~/.local/share/opencode` at launch and
holds them for the process lifetime. It also grants read access to Cursor's
`~/Library/Application Support/Cursor/User/globalStorage` session database; the
user grants these paths in Settings → Local Data Access. Under the sandbox,
`NSHomeDirectory()` returns the container — use
`Constants.realHomeDirectory`, which resolves the true home via
`getpwuid(getuid())` (`Constants.swift:133`).

**The SwiftData store is pinned to the App Group.** `AgentUsageApp.swift:66`
passes `ModelConfiguration(groupContainer: .identifier(Constants.appGroupIdentifier))`
explicitly, with an in-memory fallback when `isRunningTests`. Dropping the
`groupContainer:` argument silently moves the store and orphans existing data.

**iOS never fetches provider usage directly.** It consumes snapshots the Mac
publishes over CloudKit
(`AgentUsageKit/Sources/AgentUsageKit/Services/UsageSyncService.swift`).
`iOS/Services/iOSCredentialService.swift` exists, but the
`~/.claude/.credentials.json` path it refers to does not exist on iOS.

**New types are MainActor-isolated by default** —
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide. Mark types
`nonisolated` when they need to cross actor boundaries.

**Sparkle is dormant and unlinked.** There are zero Sparkle references in
`AgentUsage.xcodeproj`. The complete implementation remains inside an outer
comment in `UpdaterController.swift`, and its app wiring, settings UI, debug
action, and update banners are commented at their former call sites. The
`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, and
`SUScheduledCheckInterval` entries remain XML-commented in `AgentUsage/Info.plist`.
Restore these pieces only for a separate direct-distribution build; App Store and
TestFlight builds must continue using Apple's update path.

**The GitHub Actions workflows cannot trigger.** `.github/workflows/ci.yml`,
`release.yml`, and `pages.yml` contain zero non-comment lines, and a fully
commented file registers no workflow. `gh workflow run release.yml`
fails silently. CI, archiving, and distribution run on Xcode Cloud, configured in
App Store Connect — there is no `ci_scripts/` directory and no workflow
definition in this repo.

**Version lives only in `Config/Version.xcconfig`**, wired as the project-level
base configuration for Debug and Release, so every target inherits
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Adding either to a target's
build settings overrides the xcconfig — never do that. Bump by hand.

**Xcode Cloud's macOS test action never actually runs.** `LSUIElement = true`
means the menu bar app can't be launched as the XCTest host, so it fails with
`Runningboard error 5` and reports `0 tests total`; the action is marked *Not
Required To Pass*. 11 of the 20 test files are `#if os(macOS)`, so macOS-specific
code — credentials, Codex/OpenCode log sources, blog sync — has no CI coverage.
Run `xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage test` locally
before merging macOS changes.
