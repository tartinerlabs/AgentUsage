//
//  AgentUsageColors.swift
//  AgentUsageKit
//
//  Cross-target application color roles shared by the app and widgets.
//

import SwiftUI

/// Provider-neutral application colors from the AgentUsage design system.
///
/// Provider attribution is name + glyph. Usage severity remains on
/// ``UsageStatus/color``. These roles are for the app's own visual language, so
/// app and extension surfaces do not duplicate fixed RGB values.
public enum AgentUsageColors {
    /// Pacific Blue (`#7197D4`), sampled from the upper timefold surface.
    public static let iconPacificBlue = Color(red: 113 / 255, green: 151 / 255, blue: 212 / 255)

    /// Graphite (`#373A41`), sampled from the lower timefold surface.
    public static let iconGraphite = Color(red: 55 / 255, green: 58 / 255, blue: 65 / 255)

    /// Ice (`#F5F6F8`), sampled from the inner timefold highlight.
    public static let iconIce = Color(red: 245 / 255, green: 246 / 255, blue: 248 / 255)

    /// Warm off-white (`#FAF4EF`), the app-icon background field.
    public static let iconBackground = Color(red: 250 / 255, green: 244 / 255, blue: 239 / 255)

    /// Timefold Ink (`#3B6BCE`), used by the usage progress bar and every provider card.
    public static let usageProgress = Color(red: 59 / 255, green: 107 / 255, blue: 206 / 255)

    /// Pacific Blue (`#7197D4`), the lighter application-brand sibling of Timefold Ink.
    public static let brandSecondary = Color(red: 113 / 255, green: 151 / 255, blue: 212 / 255)

    /// Pampas (`#F4F3EE`), the light provider-neutral brand ground.
    public static let brandBackground = Color(red: 244 / 255, green: 243 / 255, blue: 238 / 255)

    /// Dusty Plum (`#8B5E83`), reserved for billed or over-limit usage.
    public static let extraUsageAccent = Color(red: 139 / 255, green: 94 / 255, blue: 131 / 255)
}

/// Compatibility spelling retained for existing widget call sites.
public let extraUsageAccentColor = AgentUsageColors.extraUsageAccent
