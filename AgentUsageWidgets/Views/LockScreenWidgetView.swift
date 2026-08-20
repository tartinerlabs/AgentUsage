//
//  LockScreenWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    var body: some View {
        if let usage = entry.selectedWindow {
            content(for: usage)
        } else {
            // WidgetNoDataView switches on the same family, so each accessory
            // shape gets its own empty treatment.
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    @ViewBuilder
    private func content(for usage: UsageWindow) -> some View {
        switch family {
        case .accessoryCircular:
            circularView(for: usage)
        case .accessoryRectangular:
            rectangularView(for: usage)
        case .accessoryInline:
            inlineView(for: usage)
        default:
            circularView(for: usage)
        }
    }

    // MARK: - Circular

    private func circularView(for usage: UsageWindow) -> some View {
        let status = usage.status(from: entry.date)
        let provider = entry.provider

        return Gauge(value: usage.normalized) {
            Image(systemName: provider?.iconName ?? "chart.bar.xaxis")
                .font(.caption2)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text("\(usage.percentUsed)")
                    .font(.system(.body, design: .rounded, weight: .bold))
                Image(systemName: status.icon)
                    .font(.system(size: 7, weight: .semibold))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(status.color)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: usage, provider: provider))
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint(accessibilityHint(for: usage))
    }

    // MARK: - Rectangular (Bar with text)

    private func rectangularView(for usage: UsageWindow) -> some View {
        // Derived from the entry's date, not `Date()` — WidgetKit renders every
        // entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let resetText = usage.resetDescription(from: entry.date)
        let provider = entry.provider

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let provider {
                    Label(provider.displayName, systemImage: provider.iconName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                Text(usage.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if entry.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                }
                Spacer(minLength: 4)
                Text("\(usage.percentUsed)%")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }

            Gauge(value: usage.normalized) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(status.color)

            HStack(spacing: 4) {
                Label(status.label, systemImage: status.icon)
                    .foregroundStyle(status.color)
                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                }
                Spacer(minLength: 4)
                Text(entry.isStale ? "Updated \(entry.lastUpdatedDescription)" : resetText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: usage, provider: provider))
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint(accessibilityHint(for: usage))
    }

    // MARK: - Inline (Single line text)

    private func inlineView(for usage: UsageWindow) -> some View {
        let status = usage.status(from: entry.date)
        let provider = entry.provider

        return Group {
            if let provider {
                Text("\(Image(systemName: provider.iconName)) \(provider.displayName) \(usage.percentUsed)% \(Image(systemName: status.icon))")
            } else {
                Text("\(usage.percentUsed)% \(Image(systemName: status.icon))")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: usage, provider: provider))
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint(accessibilityHint(for: usage))
    }

    private func accessibilityLabel(for usage: UsageWindow, provider: AgentUsageKit.Provider?) -> String {
        if let provider {
            return "\(provider.displayName), \(usage.displayName) usage"
        }
        return "\(usage.displayName) usage"
    }

    private func accessibilityValue(for usage: UsageWindow, status: UsageStatus) -> String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        if entry.isStale {
            parts.append("stale")
        }
        return parts.joined(separator: ", ")
    }

    private func accessibilityHint(for usage: UsageWindow) -> String {
        let freshness = "Updated \(entry.lastUpdatedDescription)"
        return "\(usage.resetDescription(from: entry.date)). \(freshness)"
    }
}

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.preview(provider: .codex)
    WidgetEntry.previewNoData()
}

#Preview("Rectangular", as: .accessoryRectangular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.previewNoData()
}

#Preview("Inline", as: .accessoryInline) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.previewNoData()
}
#endif
