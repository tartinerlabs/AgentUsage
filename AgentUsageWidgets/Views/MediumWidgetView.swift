//
//  MediumWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct MediumWidgetView: View {
    /// Two-line compact rows fit three providers in the Medium container;
    /// glances arrive most recently used first, so the fourth onward is the
    /// least active.
    private static let maxGlances = 3

    let entry: WidgetEntry

    var body: some View {
        let glances = entry.glanceWindows
        if glances.count >= 2 {
            overview(Array(glances.prefix(Self.maxGlances)))
        } else if let glance = glances.first {
            singleProvider(
                windows: Array(entry.liveWindows(for: glance.provider).prefix(2)),
                provider: glance.provider,
                fetchedAt: glance.fetchedAt
            )
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func overview(_ glances: [WidgetGlanceWindow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fetchedAt = glances.map(\.fetchedAt).max(), entry.isStale(fetchedAt: fetchedAt) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Spacer(minLength: 0)
                    WidgetFreshnessLabel(entry: entry, fetchedAt: fetchedAt)
                }
            }

            VStack(spacing: 8) {
                ForEach(glances) { glance in
                    WidgetProviderGlanceRow(
                        provider: glance.provider,
                        usage: glance.window,
                        now: entry.date,
                        style: .compact
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func singleProvider(
        windows: [UsageWindow],
        provider: AgentUsageKit.Provider,
        fetchedAt: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: provider, font: .headline)
                Spacer(minLength: 8)
                if entry.isStale(fetchedAt: fetchedAt) {
                    WidgetFreshnessLabel(entry: entry, fetchedAt: fetchedAt)
                }
            }

            Spacer(minLength: 4)

            // Medium is wide, not tall: windows sit side by side as Small-style
            // glances so the percent leads instead of stacking three-line rows.
            HStack(alignment: .top, spacing: 16) {
                ForEach(windows, id: \.windowID) { usage in
                    windowGlance(usage)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func windowGlance(_ usage: UsageWindow) -> some View {
        let status = usage.status(from: entry.date)

        return VStack(alignment: .leading, spacing: 4) {
            Text(usage.displayName)
                .font(.widgetCaption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(usage.percentUsed)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Image(systemName: status.icon)
                    .font(.title3)
                    .foregroundStyle(status.color)
                    .accessibilityHidden(true)
                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)%")
                        .font(.widgetCaption2)
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }
            }

            WidgetRedactableProgressBar(usage: usage, now: entry.date)
                .accessibilityHidden(true)

            WidgetResetLabel(usage: usage, now: entry.date)
                .font(.widgetCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.displayName) usage")
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint(usage.resetDescription(from: entry.date))
    }

    private func accessibilityValue(for usage: UsageWindow, status: UsageStatus) -> String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Medium", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.preview(provider: .codex)
    WidgetEntry.previewExtraUsage()
    WidgetEntry.previewStale()
}

#Preview("Medium — No data", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
