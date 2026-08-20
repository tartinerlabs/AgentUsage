# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Developers who use Claude Code, Codex, and other coding agents throughout the day. They need to understand subscription pressure without leaving their current task or opening several provider dashboards.

## Product Purpose

AgentUsage is a local-first usage weather station for AI coding tools. It turns provider quota windows, reset timing, token activity, and estimated cost into an accurate at-a-glance view so developers can pace work and avoid unexpected limits.

## Positioning

A native menu-bar weather station for several coding agents at once. Quota, reset, and cost are readable without leaving the current task; details live in the popover and dashboard, not in a full analytics suite.

## Operating Context

One SwiftUI product that adapts per OS. It is not a website and not an Android app.

- **macOS 15+** is the source of truth: a menu-bar agent (Release builds are `LSUIElement`) that reads local credentials, CLI logs, and provider APIs, then publishes snapshots over CloudKit.
- **iOS / iPadOS 18+** is the companion: dashboard, Home Screen and Lock Screen widgets, and Live Activities. iOS never fetches provider usage itself; it consumes the Mac-published snapshot.
- Typical scene: a developer mid-session, menu bar always present. The status item stays quiet; a click opens the popover. The dashboard, Settings, and notifications carry explanation.
- Local data lives on the Mac: Keychain credentials, security-scoped folder grants for `~/.claude`, `~/.codex`, `~/.grok`, and Cursor's session store. Notifications fire on the device that has a fresh snapshot.
- Shipping path is App Store / TestFlight via Xcode Cloud. Sparkle remains in the tree but is unlinked and must stay dormant for those builds.

## Capabilities and Constraints

- **Providers:** Claude, Codex, Cursor, and Grok are wired. OpenCode and OpenCode Go have implementations and tests but are deliberately unwired — usage is currently unreliable; do not re-enable to make a provider "work."
- **Two data seams:** live quota windows (`ProviderUsageServiceProtocol`) and local token/cost logs (`UsageLogSource` → `ProviderUsageEntry`). Check each provider's `Capability` set; Grok is token/cost only and has no live quota API.
- **macOS-only collection.** Credentials come from the Keychain (`security`), not the filesystem. Log reads require a folder grant. `NSHomeDirectory()` is the sandbox container; real home is `Constants.realHomeDirectory`.
- **iOS is a mirror.** `iOSCredentialService` exists, but the Claude credentials path it refers to does not exist on iOS.
- **Persistence** is SwiftData pinned to the App Group. Dropping `groupContainer:` orphans existing stores.
- **Version** lives only in `Config/Version.xcconfig`. Do not set `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` on a target.
- **Undecided / out of scope:** unofficial grok.com billing scrapes; restoring Sparkle except for a separate direct-distribution build; uncommenting GitHub Actions (CI is Xcode Cloud).

## Brand Commitments

- **Name:** AgentUsage.
- **Personality:** Calm, native, precise. A trustworthy macOS utility that stays quiet until its data needs attention.
- **Mark:** The **timefold** — a provider-neutral continuous interval that folds through itself and opens at a small reset notch. It expresses usage monitoring, pacing, and reset forecasting. Do not flatten it into a generic ring or traffic light. Do not use provider logos, provider colors, sparks, initials, robots, chat bubbles, or code brackets as the product mark.
- **Color anchors for the mark** live in DESIGN.md (Pacific blue, graphite, ice, warm off-white). Application accent is Timefold Ink. Status green/orange/red and Dusty Plum extra-usage are reserved roles, not brand decoration.
- **Authoritative mark target:** `Design/AppIcon/approved-timefold-mockup.png`. Production exports must be compared with it.
- **Anti-references:** a full analytics dashboard compressed into the menu bar; colorful decoration or motion that competes with live usage data; placeholder values that look like current provider data.

## Evidence on Hand

- Product and visual records: this file, `DESIGN.md`, `CLAUDE.md`.
- Mark artwork under `Design/AppIcon/` (marketing 1024, `usage-ring-1024`, Icon Composer source). The approved mockup path is the named target; compare production exports to the artwork that actually ships.
- No customer testimonials, case studies, press quotes, pricing pages, or third-party benchmarks. Do not invent them.
- `README.md` is stale (still Claude-only, still describes an archived GitHub-release build). Do not treat it as product truth.

## Product Principles

- Glance first: the highest-value state must be readable without opening the app.
- Provider before metric: establish whose quota is shown before presenting values.
- Truth over placeholders: hide unavailable or expired data instead of fabricating certainty.
- Details on demand: keep the status item quiet; put explanation in the popover and dashboard.
- Provider-neutral identity: providers may be attributed inside the product, but no provider owns the AgentUsage brand.

## Accessibility & Inclusion

Every compact visual must expose a complete VoiceOver description. Information must remain legible in light, dark, increased-contrast, and reduced-transparency environments, and color must never be the only carrier of meaning. Motion is reserved for state changes and must respect reduced-motion preferences.
