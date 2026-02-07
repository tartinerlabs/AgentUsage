//
//  MediumWidgetView.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import ClaudeMeterKit
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            metricView(title: entry.snapshot.session.windowType.displayName, usage: entry.snapshot.session)
            Divider()
            metricView(title: entry.snapshot.opus.windowType.displayName, usage: entry.snapshot.opus)

            if let sonnet = entry.snapshot.sonnet {
                Divider()
                metricView(title: sonnet.windowType.displayName, usage: sonnet)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude usage summary")
    }

    private func metricView(title: String, usage: UsageWindow) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Image(systemName: usage.trend.icon)
                    .font(.system(size: 8))
                    .foregroundStyle(trendColor(for: usage.trend))
            }

            progressRing(for: usage)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Text("\(usage.percentUsed)%")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(usage.status.color)

            if usage.isUsingExtraUsage {
                Text("Extra")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(extraUsageAccentColor)
            }

            Text(usage.timeUntilReset)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue("\(usage.percentUsed) percent, \(usage.status.label), \(usage.trend.accessibilityLabel)")
        .accessibilityHint("Resets \(usage.timeUntilReset)")
    }

    private func trendColor(for trend: UsageWindow.Trend) -> Color {
        switch trend {
        case .increasing: return .orange
        case .stable: return .secondary
        case .decreasing: return .green
        }
    }

    private func progressRing(for usage: UsageWindow) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: usage.normalized)
                .stroke(
                    usage.status.color,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview(as: .systemMedium) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}
