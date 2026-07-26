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
            WidgetNoDataView()
        }
    }

    private func content(for usage: UsageWindow) -> some View {
        // Time-dependent values are derived from the entry's date, not `Date()`:
        // WidgetKit renders every entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let trend = usage.trend(from: entry.date)
        let resetText = usage.resetDescription(from: entry.date)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(entry.metric.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Image(systemName: trend.icon)
                    .font(.caption2)
                    .foregroundStyle(trendColor(for: trend))
            }

            progressRing(for: usage, status: status)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            Text("\(usage.percentUsed)%")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(status.color)

            if usage.isUsingExtraUsage {
                Text("Extra")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(extraUsageAccentColor)
            }

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            WidgetFreshnessLabel(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.metric.displayName) usage")
        .accessibilityValue("\(usage.percentUsed) percent used, \(status.label), \(trend.accessibilityLabel)")
        .accessibilityHint("\(resetText). Updated \(entry.lastUpdatedDescription)")
    }

    private func trendColor(for trend: UsageWindow.Trend) -> Color {
        switch trend {
        case .increasing: return .orange
        case .stable: return .secondary
        case .decreasing: return .green
        }
    }

    private func progressRing(for usage: UsageWindow, status: UsageStatus) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: usage.normalized)
                .stroke(
                    status.color,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

#if DEBUG
#Preview("Small", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview(metric: .session)
    WidgetEntry.preview(metric: .opus)
}

#Preview("Small — No data", as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
