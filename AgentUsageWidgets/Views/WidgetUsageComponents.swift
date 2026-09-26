//
//  WidgetUsageComponents.swift
//  AgentUsageWidgets
//
//  Compact WidgetKit adaptations of the shared provider-card visual system.
//

import AgentUsageKit
import SwiftUI
import WidgetKit

/// Small widget text styles. The HIG asks for widget text of 11 points or
/// larger, but macOS renders caption, caption 2, and footnote at 10 points;
/// subheadline is the smallest macOS style that meets it. iOS keeps its own
/// styles, which are already 11 points or larger.
extension Font.TextStyle {
    static var widgetCaption2: Font.TextStyle {
        #if os(macOS)
        .subheadline
        #else
        .caption2
        #endif
    }

    static var widgetCaption: Font.TextStyle {
        #if os(macOS)
        .subheadline
        #else
        .caption
        #endif
    }

    static var widgetFootnote: Font.TextStyle {
        #if os(macOS)
        .subheadline
        #else
        .footnote
        #endif
    }
}

extension Font {
    static var widgetCaption2: Font { .system(.widgetCaption2) }
    static var widgetCaption: Font { .system(.widgetCaption) }
    static var widgetFootnote: Font { .system(.widgetFootnote) }
}

/// Brand wash for the system widget container. WidgetKit supplies the outer
/// shape and 16-point margins; this view must stay inside `containerBackground`
/// so StandBy and CarPlay can remove it.
struct WidgetProviderBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            AgentUsageColors.usageProgress.opacity(0.06)
        }
    }
}

/// Provider identity shared by every home-screen widget family.
struct WidgetProviderIdentity: View {
    let provider: AgentUsageKit.Provider
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider, size: 14)
                .foregroundStyle(AgentUsageColors.usageProgress)
                .widgetAccentable()
            Text(provider.displayName)
                .foregroundStyle(.primary)
        }
            .font(font)
            .fontWeight(.bold)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(provider.displayName)
    }
}

/// Reset countdown for widget rows.
///
/// Only the final hour uses a system-updating `.timer`. Longer horizons use a
/// static phrase derived from the entry date: WidgetKit reserves the widest
/// possible width for `Text(_:style:)`, which starves neighbouring titles and
/// progress bars, and the timeline already re-renders every five minutes.
struct WidgetResetLabel: View {
    let usage: UsageWindow
    let now: Date
    var includePrefix: Bool = true

    var body: some View {
        Group {
            if usage.resetsAt <= now {
                Text(includePrefix ? "Resets now" : "now")
            } else if usage.resetsAt.timeIntervalSince(now) < 3600 {
                if includePrefix {
                    Text("Resets in ") + Text(usage.resetsAt, style: .timer)
                } else {
                    Text(usage.resetsAt, style: .timer)
                }
            } else if includePrefix {
                Text(usage.resetDescription(from: now))
            } else {
                Text(usage.timeUntilReset(from: now))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// `UsageProgressBar` is a custom shape, so `.redacted` never touches it. Blank
/// the fill while a placeholder or privacy redaction is active.
struct WidgetRedactableProgressBar: View {
    @Environment(\.redactionReasons) private var redactionReasons

    let usage: UsageWindow
    let now: Date

    var body: some View {
        if redactionReasons.isEmpty {
            UsageProgressBar(usage: usage, now: now)
        } else {
            UsageProgressBar(progress: 0)
        }
    }
}

/// The widget-sized counterpart to `UsageRowView`: same title/reset hierarchy,
/// status-tinted progress track, rounded usage figure, and semantic status.
struct WidgetUsageRow: View {
    let title: String
    let usage: UsageWindow
    let now: Date

    private var status: UsageStatus {
        usage.status(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WidgetResetLabel(usage: usage, now: now)
                    .font(.widgetFootnote)
                    .foregroundStyle(.secondary)
            }

            WidgetRedactableProgressBar(usage: usage, now: now)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(usage.percentUsed)%")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                Text("used")
                    .font(.widgetFootnote)
                    .foregroundStyle(.secondary)

                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .font(.widgetFootnote)
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Label(status.label, systemImage: status.icon)
                    .font(.widgetFootnote)
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    private var accessibilityValue: String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }
}

/// One provider's glance row for Medium and Large overview widgets.
struct WidgetProviderGlanceRow: View {
    enum Style {
        /// Medium density: provider · window, percent, status icon, bar, and compact reset.
        case compact
        /// Large density: provider identity plus the canonical usage row.
        case regular
    }

    let provider: AgentUsageKit.Provider
    let usage: UsageWindow
    let now: Date
    var style: Style = .compact

    private var status: UsageStatus {
        usage.status(from: now)
    }

    var body: some View {
        switch style {
        case .compact:
            compactRow
        case .regular:
            regularRow
        }
    }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ProviderIcon(provider, size: 12)
                    .foregroundStyle(AgentUsageColors.usageProgress)
                    .widgetAccentable()
                Text(provider.displayName)
                    .fontWeight(.semibold)
                    .layoutPriority(1)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(usage.displayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(usage.percentUsed)%")
                    .font(.system(.widgetCaption, design: .rounded, weight: .bold))
                    .layoutPriority(1)
                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                    .accessibilityHidden(true)
            }
            .font(.widgetCaption)

            HStack(spacing: 8) {
                WidgetRedactableProgressBar(usage: usage, now: now)
                    .accessibilityHidden(true)
                WidgetResetLabel(usage: usage, now: now, includePrefix: false)
                    .font(.widgetCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(usage.displayName) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    private var regularRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ProviderIcon(provider, size: 14)
                    .foregroundStyle(AgentUsageColors.usageProgress)
                    .widgetAccentable()
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .layoutPriority(1)
                    .lineLimit(1)
                Text(usage.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(usage.percentUsed)%")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .layoutPriority(1)
            }

            WidgetRedactableProgressBar(usage: usage, now: now)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WidgetResetLabel(usage: usage, now: now)
                    .font(.widgetFootnote)
                    .foregroundStyle(.secondary)
                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .font(.widgetFootnote)
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Label(status.label, systemImage: status.icon)
                    .font(.widgetFootnote)
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(usage.displayName) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    private var accessibilityValue: String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }
}

/// One-line secondary window under a Large overview row: name, short bar, percent.
struct WidgetSecondaryWindowRow: View {
    let usage: UsageWindow
    let now: Date

    private var status: UsageStatus {
        usage.status(from: now)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(usage.displayName)
                .font(.widgetFootnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            WidgetRedactableProgressBar(usage: usage, now: now)
                .frame(width: 72)
                .accessibilityHidden(true)
            Text("\(usage.percentUsed)%")
                .font(.system(.widgetFootnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
            Image(systemName: status.icon)
                .font(.widgetFootnote)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
        }
        .padding(.leading, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.displayName) usage")
        .accessibilityValue("\(usage.percentUsed) percent used, \(status.label)")
        .accessibilityHint(usage.resetDescription(from: now))
    }
}
