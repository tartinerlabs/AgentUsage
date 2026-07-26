//
//  SmallWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    private var usage: UsageWindow {
        entry.selectedWindow
    }

    // Time-dependent values are derived from the entry's date, not `Date()`:
    // WidgetKit renders every entry of a timeline up front.
    private var status: UsageStatus { usage.status(from: entry.date) }
    private var trend: UsageWindow.Trend { usage.trend(from: entry.date) }
    private var resetText: String { usage.resetDescription(from: entry.date) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(entry.metric.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Image(systemName: trend.icon)
                    .font(.caption2)
                    .foregroundStyle(trendColor)
            }

            progressRing
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

    private var trendColor: Color {
        switch trend {
        case .increasing: return .orange
        case .stable: return .secondary
        case .decreasing: return .green
        }
    }

    private var progressRing: some View {
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

#Preview(as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .opus)
}
