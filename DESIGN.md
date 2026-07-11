---
version: alpha
name: AgentUsage
description: Visual identity for AgentUsage — a multi-platform SwiftUI usage "weather station" (macOS menu bar + iOS + widgets) for Claude/Codex/opencode usage.

colors:
  # Brand — defined in code, not in Assets.xcassets. See Utilities/Constants.swift:13-17
  primary: "#C15F3C"             # Crail — the app's primary brand color; usage progress-bar fill
  brand-secondary: "#DA7756"     # warm clay accent (near-duplicate of provider-claude)
  brand-background: "#F4F3EE"    # Pampas — light-mode neutral ground
  extra-usage-accent: "#8B5E83"  # Dusty Plum — RESERVED for over-limit / billed usage only

  # Status — SwiftUI system-semantic colors (auto light/dark + accessibility).
  # Hex values are sRGB approximations for tooling; the source of truth is the system color.
  status-on-track: "#34C759"     # .green
  status-warning: "#FF9500"      # .orange
  status-critical: "#FF3B30"     # .red

  # Provider accents. See Provider.swift:40-46
  provider-claude: "#D97757"     # Claude clay (note: near-duplicate of brand-secondary)
  provider-codex: "#10A37F"      # OpenAI green
  provider-open-code: "#6366F1"  # Indigo

typography:
  # Base is SwiftUI semantic Dynamic Type (SF Pro). Do NOT hardcode point sizes for body text.
  # Ranked by usage: caption > body > headline > caption2 > subheadline > footnote > title*.
  # `font` names below map to SwiftUI Font.TextStyle values.
  caption:
    font: SF Pro Text
    style: caption          # .font(.caption)
  body:
    font: SF Pro Text
    style: body             # .font(.body)
  headline:
    font: SF Pro Text
    style: headline         # .font(.headline)
    fontWeight: 600
  # === The two deliberate typographic signatures over default Dynamic Type ===
  number-prominent:
    font: SF Pro Rounded
    fontSize: 20            # points (16 in compact mode)
    fontWeight: 700
    design: rounded         # .system(size: 20, weight: .bold, design: .rounded)
  menubar-numeric:
    font: SF Mono
    fontSize: 9             # points (11 for a single pinned value)
    fontWeight: 600
    design: monospaced      # .system(size: 9, weight: .semibold, design: .monospaced)
  cost-label:
    font: SF Pro Text
    style: caption2
    textCase: uppercase     # .textCase(.uppercase)
    letterSpacing: 0.5      # .tracking(0.5)

spacing:
  # px values == SwiftUI points (the linter requires px/rem/em units).
  # Primary rhythm is 4 / 8 / 12 / 16 / 20 (multiples of 2/4).
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  2xl: 24px

rounded:
  # Corner radii; px == SwiftUI points.
  sm: 4px   # progress bars, badges, extra-usage bars
  md: 12px  # provider cards
  lg: 16px  # iOS usage cards

components:
  # Only spec sub-tokens are used here (backgroundColor, textColor, typography,
  # rounded, padding, size, height, width). SwiftUI-specific details — borders,
  # track colors, line widths/caps, opacities — live in the Components prose below.
  card-provider:                 # ProviderCardView.swift:77-86 — one card per provider
    backgroundColor: "{colors.provider-claude}"  # rendered at 0.06 opacity; border at 0.15
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"      # 12px in compact mode
  card-provider-codex:           # same card, Codex accent
    backgroundColor: "{colors.provider-codex}"
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"
  card-provider-open-code:       # same card, opencode accent
    backgroundColor: "{colors.provider-open-code}"
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"
  card-usage:                    # UsageCardView.swift:49-53 — background is .regularMaterial
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
  badge:                         # plan-name / service-down pills
    backgroundColor: "{colors.provider-claude}"  # accent at 0.12 opacity
    rounded: "{rounded.sm}"
    padding: "2px 6px"
  extra-usage-bar:               # over-limit / billed usage indicator
    backgroundColor: "{colors.extra-usage-accent}"
    rounded: "{rounded.sm}"
  progress-bar:                  # UsageRowView.swift — fill over a secondary @ 0.2 track
    backgroundColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    height: "8px"
  progress-ring:                 # UsageCardView.swift — status-colored, lineWidth 8, round cap
    size: "60px"
---

# AgentUsage Design System

## Overview

AgentUsage is a **usage "weather station"**: at a glance, a color tells you whether your
Claude/Codex/opencode usage is on-track (green), warming up (orange), or about to hit the wall
(red). The identity is calm and utilitarian — a menu-bar glyph and a stack of quiet cards, with
color and a single accent doing all the signalling. Nothing shouts until it needs to.

**This is a SwiftUI system, documented in the DESIGN.md format.** The
[DESIGN.md spec](https://github.com/google-labs-code/design.md) is web/CSS-oriented
(px, hex, `fontFamily`). AgentUsage is native SwiftUI across macOS, iOS, and WidgetKit, so this
file adapts the format: colors stay as hex (they are CSS-valid and lint cleanly), spacing and
radii are **points**, and typography/iconography use **SF Pro Dynamic Type styles** and **SF
Symbol names** rather than web font stacks. Read `font`/`design`/`style` values as SwiftUI
`Font` parameters, not CSS.

All brand colors live in Swift code (`Utilities/Constants.swift`,
`AgentUsageKit/Sources/AgentUsageKit/Models/`), not in `Assets.xcassets` — the accent-color
asset sets are intentionally left at system default.

## Colors

Three families, each with a distinct job:

- **Brand (Crail + Pampas).** `primary` `#C15F3C` (Crail) is the usage progress-bar fill — the one
  place the app's own warm clay appears prominently. `brand-background` `#F4F3EE` (Pampas) is the
  light neutral ground. These are fixed sRGB values and do **not** adapt to dark mode.
- **Status (system-semantic).** On-track/warning/critical map to SwiftUI `.green` / `.orange` /
  `.red`. Because they are system colors, they adapt automatically to light/dark and
  accessibility settings. This is deliberate: usage severity must remain legible in every
  appearance, so it is never a hardcoded hex.
- **Provider accents.** Each provider owns a tint used for its card and glyph: Claude clay
  `#D97757`, Codex/OpenAI green `#10A37F`, opencode indigo `#6366F1`.
- **Extra-usage accent (Dusty Plum `#8B5E83`).** The single non-brand, non-status accent,
  reserved **exclusively** for over-limit / billed usage indicators. Its scarcity is what makes
  it meaningful — do not reuse it for decoration. Mirrored publicly as
  `extraUsageAccentColor` in AgentUsageKit so widgets can reference it.

> **Known duplication:** `brand-secondary` `#DA7756` and `provider-claude` `#D97757` are two
> nearly-identical clay tones that coexist. Treat `provider-claude` as authoritative for Claude
> provider UI; prefer consolidating if you touch both.

## Typography

The type system is **SF Pro Dynamic Type first**. Body and label text use semantic styles
(`.caption` is by far the most common, followed by `.body`, `.headline`, `.subheadline`,
`.footnote`, and the `.title` family) so text scales with the user's accessibility settings.
Prefer a semantic style over a fixed point size in almost all cases.

Two treatments are the intentional signatures on top of that base:

1. **Rounded numerals** — prominent figures (costs, headline stats) use
   `.system(size: 20, weight: .bold, design: .rounded)` (16pt compact). `design: .rounded` is the
   house style for any number the eye should land on.
2. **Monospaced menu-bar numerics** — the macOS menu-bar glyph packs tiny values in SF Mono
   (`.system(size: 10, weight: .medium, design: .monospaced)`; labels 8pt, arrows 6pt) so digits
   don't jitter as they change.

Weights: `.bold` for headline numbers and provider names, `.semibold` for row titles and badges,
`.medium` for secondary labels. Cost labels are uppercased with `.tracking(0.5)`.

## Layout

Spacing follows a **4 / 8 / 12 / 16 / 20** rhythm (multiples of 2/4), with `24` for larger gaps.
Cards use `.padding()` (system default ≈16) or an explicit 16/12-compact.

Opacity is a structural tool with fixed conventions:

| Opacity | Role |
|---------|------|
| `0.06`  | Provider-card fill (accent tint) |
| `0.12`  | Badge fill (accent tint) |
| `0.15`  | Card border stroke; tick dividers |
| `0.20`  | Progress-bar track (`secondary`) |

## Elevation & Depth

Depth comes from **material translucency, not shadows.** `.regularMaterial` is the standard card
and panel background; `.bar` material appears in a few places. There are **no drop shadows and no
gradients** anywhere in the app — layering reads through translucency and the subtle
tinted-fill/border pairing on cards.

## Shapes

Corner radius is assigned by component scale:

- **4pt** — small elements: progress-bar tracks and fills, plan badges, extra-usage bars.
- **12pt** — provider cards (`ProviderCardView`).
- **16pt** — iOS usage cards (`UsageCardView`).

## Components

- **`UsageRowView`** — the linear progress row: title + reset time, a `primary` (Crail) fill over a
  `secondary` @ 0.2 track (height 8, radius 4) with 1pt tick dividers at 25/50/75%, plus a
  `% used` + status `Label` stats row. Optional 7×7 status dot.
- **`ProviderCardView`** — the primary card. Header (provider glyph + name + plan badge + optional
  service-down badge), a stack of `UsageRowView`s, optional reset-credits line, optional
  extra-usage bar, and a cost section. Fill = provider accent @ 0.06, border @ 0.15. Has a
  `compact` mode toggling paddings/fonts.
- **`UsageCardView`** — iOS/widget card built around a **circular progress ring** (60×60,
  lineWidth 8, round cap, animated) with a large `.title`-bold percentage in the status color,
  over `.regularMaterial` at radius 16.
- **`SparklineView`** (macOS) — Canvas-drawn line/bar sparkline (30×10, lineWidth 1); drawn at
  `white` @ 0.8, empty state at `color` @ 0.25.
- **`MenuBarIconView`** (macOS) — an adaptive monochrome template `NSImage`. Claude and Codex
  render in that order as a 16pt provider mark plus one 11pt percentage or two tightly stacked
  9pt percentages. Up to two windows are pinned per provider; missing and expired values consume
  no space. Visible labels, trend arrows, reset countdowns, and extra-usage cost stay in the
  popover rather than the status strip.
- **Widget & Live Activity gauges** — lock-screen uses SwiftUI `Gauge` (`.accessoryCircular` /
  `.accessoryLinear`) colored by `status.color` with matching `.keylineTint`.

Status-bearing components use `UsageStatus` as the single source of truth for "how bad is it."
The menu-bar strip is intentionally neutral: macOS applies the template tint, while its values
and VoiceOver description communicate usage without squeezing severity decoration into 22pt.

## Status System

`UsageStatus` (`AgentUsageKit/.../UsageData.swift`) has three cases, each pairing a color, an SF
Symbol, and a label:

| Status | Color | SF Symbol | Label |
|--------|-------|-----------|-------|
| `.onTrack`  | `.green`  | `checkmark.circle.fill`         | Low |
| `.warning`  | `.orange` | `exclamationmark.triangle.fill` | Moderate |
| `.critical` | `.red`    | `xmark.circle.fill`             | High |

**Per-window status** is computed as: expired windows → `.onTrack`; then **absolute thresholds**
(utilization ≥ 90 → critical, ≥ 75 → warning); otherwise **pace-based** — compare actual
utilization to expected-for-elapsed-time, where a lead of ≤10 is on-track, ≤25 is warning, else
critical.

**Trend arrows** use the same pace delta: `arrow.up.right` (orange) increasing, `arrow.right`
stable, `arrow.down.right` (green) decreasing.

**Overall status** is the **worst** across all windows (`critical > warning > onTrack`),
defaulting to on-track when there is no data.

Provider glyphs: the compact menu-bar strip uses the official Claude spark and OpenAI Blossom as
unchanged monochrome template marks. Other surfaces retain Claude `sparkles`, Codex
`chevron.left.forwardslash.chevron.right`, and opencode `curlybraces` until the broader
provider-logo work is completed; those SF Symbols are also the menu-bar fallbacks.

## Do's and Don'ts

- **Do** use the semantic status colors (`UsageStatus.color`) for anything severity-related. They
  adapt to light/dark and accessibility for free.
- **Don't** hardcode `.green` / `.orange` / `.red` at call sites — go through `UsageStatus` so the
  thresholds stay centralized.
- **Do** reserve `extra-usage-accent` (Dusty Plum) for over-limit / billed usage only. Its meaning
  depends on its scarcity.
- **Do** prefer Dynamic Type styles (`.caption`, `.body`, `.headline`, …) over fixed point sizes,
  except for the deliberate menu-bar numerics and rounded-number signatures.
- **Do** use `design: .rounded` for any headline number the user should read at a glance.
- **Do** build depth from `.regularMaterial` and tinted fills/borders. **Don't** add drop shadows
  or gradients — the system has none, and adding them breaks the flat, translucent look.
- **Do** pair every status color with its matching SF Symbol; never show one without the other.
  A neutral component such as the template-tinted menu-bar strip may omit both.
