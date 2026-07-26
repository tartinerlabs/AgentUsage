//
//  MediumWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(for: snapshot)
        } else {
            WidgetNoDataView()
        }
    }

    private func content(for snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                metricView(title: snapshot.session.windowType.displayName, usage: snapshot.session)
                Divider()
                metricView(title: snapshot.opus.windowType.displayName, usage: snapshot.opus)

                if let sonnet = snapshot.sonnet {
                    Divider()
                    metricView(title: sonnet.windowType.displayName, usage: sonnet)
                }

                if let design = snapshot.design {
                    Divider()
                    metricView(title: design.windowType.displayName, usage: design)
                }

                if let fable = snapshot.fable {
                    Divider()
                    metricView(title: fable.windowType.displayName, usage: fable)
                }
            }

            WidgetFreshnessLabel(entry: entry)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude usage summary")
    }

    private func metricView(title: String, usage: UsageWindow) -> some View {
        // Time-dependent values come from the entry's date, not `Date()`:
        // WidgetKit renders every entry of a timeline up front.
        let status = usage.status(from: entry.date)
        let trend = usage.trend(from: entry.date)
        let resetText = usage.resetDescription(from: entry.date)

        return VStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Image(systemName: trend.icon)
                    .font(.system(size: 8))
                    .foregroundStyle(trendColor(for: trend))
            }

            progressRing(for: usage, status: status)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Text("\(usage.percentUsed)%")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(status.color)

            if usage.isUsingExtraUsage {
                Text("Extra")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(extraUsageAccentColor)
            }

            Text(usage.timeUntilReset(from: entry.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue("\(usage.percentUsed) percent, \(status.label), \(trend.accessibilityLabel)")
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
#Preview("Medium", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview()
}

#Preview("Medium — No data", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
