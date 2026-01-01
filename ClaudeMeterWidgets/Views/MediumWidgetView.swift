//
//  MediumWidgetView.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            metricView(title: "Session", usage: entry.snapshot.session)
            Divider()
            metricView(title: "Opus", usage: entry.snapshot.opus)

            if let sonnet = entry.snapshot.sonnet {
                Divider()
                metricView(title: "Sonnet", usage: sonnet)
            }
        }
        .padding(.horizontal, 8)
    }

    private func metricView(title: String, usage: UsageWindow) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            progressRing(for: usage)
                .frame(width: 44, height: 44)

            Text("\(usage.percentUsed)%")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(usage.status.color)

            Text(usage.timeUntilReset)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
