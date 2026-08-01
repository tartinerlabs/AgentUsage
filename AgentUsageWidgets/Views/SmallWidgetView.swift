//
//  SmallWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if let usage = entry.selectedWindow {
            content(for: usage)
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func content(for usage: UsageWindow) -> some View {
        // Time-dependent values are derived from the entry's date, not `Date()`:
        // WidgetKit renders every entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let resetText = usage.resetDescription(from: entry.date)

        return VStack(alignment: .leading, spacing: 8) {
            WidgetProviderIdentity(provider: entry.provider, font: .caption)
            WidgetUsageRow(
                title: usage.displayName,
                usage: usage,
                now: entry.date
            )
            Spacer(minLength: 0)
            WidgetFreshnessLabel(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.provider.displayName), \(usage.displayName) usage")
        .accessibilityValue(accessibilityValue(for: usage, status: status))
        .accessibilityHint("\(resetText). Updated \(entry.lastUpdatedDescription)")
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
}

#if DEBUG
#Preview("Small", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview(provider: .claude)
    WidgetEntry.preview(provider: .codex)
}

#Preview("Small — No data", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
