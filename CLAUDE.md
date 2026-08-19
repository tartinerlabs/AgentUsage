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
  (`claude`, `codex`, `openCode`, `openCodeGo`, `cursor`, `grok`). Each carries a `Capability` set
  (`.rateWindows` for live quota windows, `.tokenCost` for token/cost from local
  logs), a `pricingProviderKey` ("anthropic" / "openai" / "xai"), and a `family` rollup.
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
bookmarks for `~/.claude`, `~/.codex`, `~/.local/share/opencode`, and `~/.grok` at launch and
holds them for the process lifetime. It also grants read access to Cursor's
`~/Library/Application Support/Cursor/User/globalStorage` session database; the
user grants these paths in Settings → Local Data Access. Under the sandbox,
`NSHomeDirectory()` returns the container — use
`Constants.realHomeDirectory`, which resolves the true home via
`getpwuid(getuid())` (`Constants.swift:133`).

**Grok has no live quota API.** `Provider.grok` is `.tokenCost` only. Grok Build
does not log billable input/output tokens; `GrokLogSource` estimates them from
the per-turn context-fill curve in `updates.jsonl`. Do not add an unofficial
grok.com billing scrape to make rate windows "work".

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
App Store Connect. `ci_scripts/ci_pre_xcodebuild.sh` strips restricted macOS
entitlements (`keychain-access-groups`, iCloud) from the Test action host so
Runningboard can spawn it; do not add those keys back to the Cloud checkout.

**Version lives only in `Config/Version.xcconfig`**, wired as the project-level
base configuration for Debug and Release, so every target inherits
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Adding either to a target's
build settings overrides the xcconfig — never do that. Bump by hand.

**Shipping macOS builds are a menu bar agent; Debug is not.** Release sets
`INFOPLIST_KEY_LSUIElement[sdk=macosx*] = YES` so archived/TestFlight builds stay
out of the Dock. Debug leaves it `NO` so Xcode Cloud and local XCTest can launch
the test host. Putting `LSUIElement` back in `AgentUsage/Info.plist` wins over
the generated key and, together with restricted Debug entitlements, brings back
`Runningboard error 5` (`Could not launch “AgentUsageTests”`). Xcode Cloud does
not embed a Mac development profile for Keychain Sharing or iCloud on the test
host — that is why `ci_pre_xcodebuild.sh` removes those keys for macOS Test.

**The shared scheme’s default test plan is unit tests only**
(`AgentUsage.xctestplan`). Xcode Cloud “Use Scheme Settings” follows that plan,
so PR Validation can be marked Required to Pass once macOS is green. UI tests
live in `AgentUsageUI.xctestplan` — run them locally (and optionally point the
iOS Cloud test action at that plan). A menu bar extra is not a reliable Cloud
macOS UI destination. Much of the unit suite is `#if os(macOS)` (credentials,
Codex/OpenCode log sources, blog sync). Still run
`xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage test` locally
before merging macOS changes.
