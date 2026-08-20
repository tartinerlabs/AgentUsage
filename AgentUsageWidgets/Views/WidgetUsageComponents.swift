//
//  WidgetUsageComponents.swift
//  AgentUsageWidgets
//
//  Compact WidgetKit adaptations of the shared provider-card visual system.
//

import AgentUsageKit
import SwiftUI
import WidgetKit

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

/// System-updating reset text so the countdown moves between timeline entries.
struct WidgetResetLabel: View {
    let resetsAt: Date
    let now: Date
    var includePrefix: Bool = true

    var body: some View {
        Group {
            if resetsAt <= now {
                Text(includePrefix ? "Resets now" : "now")
            } else if resetsAt.timeIntervalSince(now) < 3600 {
                if includePrefix {
                    Text("Resets in ") + Text(resetsAt, style: .timer)
                } else {
                    Text(resetsAt, style: .timer)
                }
            } else if includePrefix {
                Text("Resets ") + Text(resetsAt, style: .relative)
            } else {
                Text(resetsAt, style: .relative)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// The widget-sized counterpart to `UsageRowView`: same title/reset hierarchy,
/// canonical Timefold Ink progress track, rounded usage figure, and semantic status.
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
                WidgetResetLabel(resetsAt: usage.resetsAt, now: now)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            UsageProgressBar(usage: usage)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(usage.percentUsed)%")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                Text("used")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .font(.footnote)
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Label(status.label, systemImage: status.icon)
                    .font(.footnote)
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
                    .font(.system(.caption, design: .rounded, weight: .bold))
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
            .font(.caption)

            HStack(spacing: 8) {
                UsageProgressBar(usage: usage)
                    .accessibilityHidden(true)
                WidgetResetLabel(resetsAt: usage.resetsAt, now: now, includePrefix: false)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(usage.displayName) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    private var regularRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetProviderIdentity(provider: provider, font: .subheadline)
            WidgetUsageRow(title: usage.displayName, usage: usage, now: now)
        }
        .accessibilityElement(children: .contain)
    }

    private var accessibilityValue: String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }
}
