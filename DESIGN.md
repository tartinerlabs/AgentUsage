---
version: alpha
name: AgentUsage
description: Visual identity for AgentUsage — a multi-platform SwiftUI usage "weather station" (macOS menu bar + iOS + widgets) for Claude, Codex, Cursor, Grok, and enabled OpenCode usage.

colors:
  # Provider-neutral identity — approved app-icon color anchors.
  # These sample the dimensional artwork; they are not instructions to flatten its gradients.
  icon-pacific-blue: "#7197D4"  # upper timefold surface
  icon-graphite: "#373A41"      # lower timefold surface
  icon-ice: "#F5F6F8"           # inner fold highlight
  icon-background: "#FAF4EF"    # warm off-white app-icon field

  # Application UI — defined in code, not in Assets.xcassets. See AgentUsageKit/.../Design/AgentUsageColors.swift
  primary: "#3B6BCE"             # Timefold Ink — light-mode primary; usage progress-bar fill
  primary-dark: "#7197D4"        # Pacific Blue — dark-mode primary (4.5:1 on #1C1C1E)
  brand-secondary: "#7197D4"     # Pacific Blue — lighter application sibling (same sample as icon-pacific-blue)
  brand-background: "#F4F3EE"    # Pampas — light-mode neutral ground
  extra-usage-accent: "#8B5E83"  # Dusty Plum — RESERVED for over-limit / billed usage only

  # Status — SwiftUI system-semantic colors (auto light/dark + accessibility).
  # Hex values are sRGB approximations for tooling; the source of truth is the system color.
  status-on-track: "#34C759"     # .green
  status-warning: "#FF9500"      # .orange
  status-critical: "#FF3B30"     # .red

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
  lg: 16px  # iOS utility and state cards

components:
  # Only spec sub-tokens are used here (backgroundColor, textColor, typography,
  # rounded, padding, size, height, width). SwiftUI-specific details — borders,
  # track colors, line widths/caps, opacities — live in the Components prose below.
  card-provider:                 # ProviderCardView — one Timefold Ink card per provider
    backgroundColor: "{colors.primary}"  # rendered at 0.06 opacity; border at 0.15
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"      # 12px in compact mode
  badge:                         # plan-name / service-down pills
    backgroundColor: "{colors.primary}"  # Timefold Ink at 0.12 opacity
    rounded: "{rounded.sm}"
    padding: "2px 6px"
  extra-usage-bar:               # over-limit / billed usage indicator
    backgroundColor: "{colors.extra-usage-accent}"
    rounded: "{rounded.sm}"
  progress-bar:                  # UsageRowView.swift — fill over a secondary @ 0.2 track
    backgroundColor: "{colors.primary}"
    rounded: "{rounded.sm}"
    height: "8px"
---

# AgentUsage Design System

## Overview

AgentUsage is a **usage "weather station"**: at a glance, a color tells you whether your
Claude/Codex/opencode usage is on-track (green), warming up (orange), or about to hit the wall
(red). The identity is calm and utilitarian — a menu-bar glyph and a stack of quiet cards, with
color and a single accent doing all the signalling. Nothing shouts until it needs to.

The provider-neutral product mark is the **timefold**: one continuous interval folding through
itself, with an open reset notch on the right. Its Pacific-blue upper surface and graphite lower
surface represent measured usage over time without borrowing the identity of any provider. The
mark is deliberately dimensional; its overlap, inner ice highlight, and restrained material
depth are part of the identity rather than optional decoration.

**This is a SwiftUI system, documented in the DESIGN.md format.** The
[DESIGN.md spec](https://github.com/google-labs-code/design.md) is web/CSS-oriented
(px, hex, `fontFamily`). AgentUsage is native SwiftUI across macOS, iOS, and WidgetKit, so this
file adapts the format: colors stay as hex (they are CSS-valid and lint cleanly), spacing and
radii are **points**, and typography/iconography use **SF Pro Dynamic Type styles** and **SF
Symbol names** rather than web font stacks. Read `font`/`design`/`style` values as SwiftUI
`Font` parameters, not CSS.

Application UI colors live in Swift code
(`AgentUsageKit/Sources/AgentUsageKit/Design/AgentUsageColors.swift`, with app-target aliases in
`Utilities/Constants.swift`), not in `Assets.xcassets` — the accent-color asset sets are
intentionally left at system default. App-icon artwork lives separately under `Design/AppIcon/`;
do not infer its production colors from the application accent tokens.

**The iOS dashboard is the canonical visual reference for application UI.** Its
`ProviderCardView` + `UsageRowView` pairing defines provider attribution, hierarchy, spacing,
linear progress, rounded numerals, and status presentation. macOS and WidgetKit adapt that
grammar to their native containers and density constraints; compact widget or menu-bar
treatments must never become the source of a competing product-wide style.

## Colors

Four families, each with a distinct job:

- **Provider-neutral identity (Pacific blue + graphite + ice).** The approved timefold artwork
  uses Pacific blue `#7197D4` as the upper-surface anchor, graphite `#373A41` as the lower-surface
  anchor, and ice `#F5F6F8` for the inner highlight, on warm off-white `#FAF4EF`. These values are
  representative points within dimensional gradients, not flat-fill replacements. They govern
  the app icon and product-level identity, not usage severity or provider attribution.

- **Application accent (Timefold Ink + Pampas).** `primary` is Timefold Ink `#3B6BCE` in
  light appearance — the usage progress-bar fill and the single provider-card tint (icons,
  plan badges, cost figures, card fill @ 0.06, border @ 0.15). It is the icon's azure hue,
  quieted and deepened so it holds as text, tint, and fill without reading as Claude or
  system blue. The same hex is only about 3.4:1 on the standard dark background `#1C1C1E`,
  below the 4.5:1 small-text threshold used by caption plan badges, so dark mode resolves
  `primary` to Pacific Blue `#7197D4` (`primary-dark`, ~5.7:1). `brand-secondary` is that
  same Pacific Blue sample in every appearance. Attribution is name + SF Symbol, not a
  per-provider hue. `brand-background` `#F4F3EE` (Pampas) is the light neutral ground and
  stays fixed sRGB. These tokens are not a substitute for the dimensional app-icon palette.
- **Status (system-semantic).** On-track/warning/critical map to SwiftUI `.green` / `.orange` /
  `.red`. Because they are system colors, they adapt automatically to light/dark and
  accessibility settings. This is deliberate: usage severity must remain legible in every
  appearance, so it is never a hardcoded hex.
- **Extra-usage accent (Dusty Plum `#8B5E83`).** The single non-brand, non-status accent,
  reserved **exclusively** for over-limit / billed usage indicators. Its scarcity is what makes
  it meaningful — do not reuse it for decoration. Mirrored publicly as
  `AgentUsageColors.extraUsageAccent` in AgentUsageKit so widgets can reference it.

## App Icon & Brand Mark

`Design/AppIcon/approved-timefold-mockup.png` is the authoritative visual target. The timefold
must read as a single continuous measured interval: a blue upper fold passes over a graphite
lower fold, an ice-lit inner turn preserves the sense of material thickness, and the small open
notch at the right suggests a reset boundary. Preserve this topology in every appearance.

Production requirements:

- Keep the mark provider-neutral. Do not add provider logos or colors, Claude-like sparks,
  initials, robots, chat bubbles, code brackets, or model-specific motifs.
- Do not use red, orange, or green status colors in the product mark. Those colors remain
  reserved for live usage severity in the interface.
- Do not flatten the mark. Preserve the overlapping surfaces, inner fold, restrained gradients,
  edge highlights, and subtle depth visible in the approved mockup. Avoid text and excessive
  detail.
- A transparent source must keep all mark pixels fully opaque; only the exterior background may
  be transparent. Background removal must not convert the blue or graphite surfaces into
  semi-transparent pixels.
- Icon Composer may add a subtle Liquid Glass treatment, with no more than four groups, but its
  translucency or appearance processing must not materially wash out or recolor the approved
  Pacific-blue and graphite anchors. Compare every export directly with the approved mockup.
- Validate Default, Dark, Mono, and iOS tinted appearances at 1024, 128, 32, and 16 points. At
  small sizes, the outer loop, central opening, and reset notch must remain unmistakable.

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
| `0.06`  | Provider-card fill (Timefold Ink) |
| `0.12`  | Badge fill (Timefold Ink) |
| `0.15`  | Card border stroke; tick dividers |
| `0.20`  | Progress-bar track (`secondary`) |

## Elevation & Depth

In application surfaces, depth comes from **material translucency, not shadows.** `.regularMaterial` is the standard card
and panel background; `.bar` material appears in a few places. There are **no drop shadows and no
gradients** in the interface — layering reads through translucency and the subtle
tinted-fill/border pairing on cards. The dimensional timefold app icon is the deliberate
exception: its gradients, edge highlights, inner fold, and restrained shadowing are required to
communicate its layered form.

## Shapes

Corner radius is assigned by component scale:

- **4pt** — small elements: progress-bar tracks and fills, plan badges, extra-usage bars.
- **12pt** — provider cards (`ProviderCardView`).
- **16pt** — iOS utility cards, including Live Activity controls and dashboard states.

## Components

- **`UsageRowView`** — the linear progress row: title + reset time, a `primary` (Timefold Ink) fill over a
  `secondary` @ 0.2 track (height 8, radius 4) with 1pt tick dividers at 25/50/75%, plus a
  `% used` + status `Label` stats row. Optional 7×7 status dot.
- **`ProviderCardView`** — the only provider surface on macOS and iOS. Header (provider glyph +
  name + plan badge + optional service-down badge), a stack of linear `UsageRowView`s, optional
  reset-credits line, optional extra-usage bar, and a cost section. `.detail` also shows links,
  a service-down banner, yesterday, sparkline, effort, and models when those fields exist. Fill
  = Timefold Ink @ 0.06, border @ 0.15. `compact` toggles paddings/fonts only. The iOS dashboard is a
  `.summary` stack in `availableProviders` order; the iOS/iPad provider destination and the
  macOS dashboard/popover provider page use `.detail`.
- **`SparklineView`** — Canvas-drawn line/bar sparkline (30×10, lineWidth 1); drawn at Timefold Ink,
  empty state at `color` @ 0.25.
- **`MenuBarIconView`** (macOS) — an adaptive monochrome template `NSImage`. Pinned providers
  render as a 16pt mark plus one 11pt percentage or two tightly stacked 9pt percentages. Up to
  two windows are pinned per provider; missing and expired values consume no space. Visible
  labels, trend arrows, reset countdowns, and extra-usage cost stay in the popover rather than
  the status strip.
- **Live Activity control card** (iOS) — one `.regularMaterial`, 16pt-radius utility card below
  the provider stack. Native Provider and Window pickers list only non-expired windows from all
  available provider snapshots. Start creates one activity, Switch updates that activity in
  place, and Stop ends it. An opt-in toggle auto-pins a short at-limit window when the scene is
  active. Disabled authorization remains visible with an Open Settings action;
  unavailable-window and start-error states stay inline in the same card.
- **Home Screen widgets** — adapt the iOS provider-card hierarchy rather than inventing a
  widget-only style: provider identity first, compact `UsageProgressBar` rows in Timefold Ink, rounded
  percentage numerals, semantic status icon + label, reset timing, and freshness. Use the widget
  container itself as the surface instead of nesting a second card inside it.
- **Accessory widgets & Live Activities** — where the platform shape requires a gauge, use
  SwiftUI `Gauge` (`.accessoryCircular` / `.accessoryLinear`) colored by `status.color` with
  matching `.keylineTint`. Live Activity content carries the selected provider and stable window
  ID so Claude, Codex, Cursor, Grok, and future enabled providers share the same presentation.
  At 100% the compact Dynamic Island shows the reset timer instead of the percentage. When the
  tracked window resets, the activity presents a brief "Limit reset" state and dismisses after
  30 seconds.

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
Provider marks are attribution inside provider-specific UI only; they must never become the
AgentUsage app icon or product-level brand mark.

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
- **Do** take cross-surface visual decisions from the iOS provider card and usage row. **Don't**
  promote a WidgetKit family-specific compromise into the shared app style.
