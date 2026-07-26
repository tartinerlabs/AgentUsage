//
//  LargeWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(for: snapshot)
        } else {
            WidgetNoDataView()
        }
    }

    private func content(for snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                WidgetFreshnessLabel(entry: entry, font: .caption)
            }

            Divider()

            // Usage rows
            usageRow(title: snapshot.session.windowType.displayName, usage: snapshot.session)
            usageRow(title: snapshot.opus.windowType.displayName, usage: snapshot.opus)

            if let sonnet = snapshot.sonnet {
                usageRow(title: sonnet.windowType.displayName, usage: sonnet)
            }

            if let design = snapshot.design {
                usageRow(title: design.windowType.displayName, usage: design)
            }

            if let fable = snapshot.fable {
                usageRow(title: fable.windowType.displayName, usage: fable)
            }

            Spacer()
        }
        .padding(4)
    }

    private func usageRow(title: String, usage: UsageWindow) -> some View {
        // Time-dependent values come from the entry's date, not `Date()`:
        // WidgetKit renders every entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let trend = usage.trend(from: entry.date)
        let resetText = usage.resetDescription(from: entry.date)

        return HStack(spacing: 12) {
            progressRing(for: usage, status: status)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: trend.icon)
                        .font(.caption2)
                        .foregroundStyle(trendColor(for: trend))
                }
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(usage.percentUsed)%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(status.color)
                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .font(.caption2)
                        .foregroundStyle(extraUsageAccentColor)
                }
                Label(status.label, systemImage: status.icon)
                    .font(.caption2)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue("\(usage.percentUsed) percent used, \(status.label), \(trend.accessibilityLabel)")
        .accessibilityHint(resetText)
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
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: usage.normalized)
                .stroke(
                    status.color,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

#if DEBUG
#Preview("Large", as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview()
}

#Preview("Large — No data", as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
