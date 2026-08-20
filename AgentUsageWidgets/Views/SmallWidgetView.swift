//
//  SmallWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct SmallWidgetView: View {
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    let entry: WidgetEntry

    var body: some View {
        if let usage = entry.selectedWindow, let provider = entry.provider {
            content(for: usage, provider: provider)
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func content(for usage: UsageWindow, provider: AgentUsageKit.Provider) -> some View {
        // Time-dependent values are derived from the entry's date, not `Date()`:
        // WidgetKit renders every entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let isStandBy = !showsBackground

        return VStack(alignment: .leading, spacing: 8) {
            header(provider: provider, isStandBy: isStandBy)
            Spacer(minLength: 4)
            hero(for: usage, status: status, showBar: !isStandBy)
            Spacer(minLength: 4)
            footer(for: usage, isStandBy: isStandBy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(usage.displayName) usage")
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint(accessibilityHint(for: usage))
    }

    private func header(provider: AgentUsageKit.Provider, isStandBy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            WidgetProviderIdentity(provider: provider, font: .caption)
            Spacer(minLength: 4)
            if entry.isStale, !isStandBy {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(UsageStatus.warning.color)
                    .accessibilityHidden(true)
            }
        }
    }

    private func hero(
        for usage: UsageWindow,
        status: UsageStatus,
        showBar: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(usage.percentUsed)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Image(systemName: status.icon)
                    .font(.title3)
                    .foregroundStyle(status.color)
                    .accessibilityHidden(true)
            }

            if usage.isUsingExtraUsage {
                Text("+\(usage.extraUsagePercent)% extra")
                    .font(.caption2)
                    .foregroundStyle(AgentUsageColors.extraUsageAccent)
                    .lineLimit(1)
            }

            if showBar {
                UsageProgressBar(usage: usage)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func footer(for usage: UsageWindow, isStandBy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(usage.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)

            if entry.isStale, !isStandBy {
                staleUpdatedLabel
            } else {
                WidgetResetLabel(resetsAt: usage.resetsAt, now: entry.date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var staleUpdatedLabel: some View {
        HStack(spacing: 3) {
            Text("Updated")
            if let fetchedAt = entry.providerSnapshot?.fetchedAt {
                Text(fetchedAt, style: .relative)
            } else {
                Text(entry.lastUpdatedDescription)
            }
        }
        .font(.caption2)
        .foregroundStyle(UsageStatus.warning.color)
        .lineLimit(1)
        .monospacedDigit()
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
        "\(usage.resetDescription(from: entry.date)). Updated \(entry.lastUpdatedDescription)"
    }
}

#if DEBUG
#Preview("Small", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.preview(provider: .claude)
    WidgetEntry.preview(provider: .codex)
    WidgetEntry.preview(provider: .cursor)
    WidgetEntry.previewExtraUsage()
    WidgetEntry.previewAtLimit()
    WidgetEntry.previewStale()
}

#Preview("Small — No data", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}

#Preview("Small — Accented") {
    SmallWidgetView(entry: .preview(provider: .claude))
        .environment(\.widgetRenderingMode, .accented)
        .containerBackground(for: .widget) {
            WidgetProviderBackground()
        }
}
#endif
