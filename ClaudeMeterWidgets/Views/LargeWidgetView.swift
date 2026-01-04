//
//  LargeWidgetView.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                Text(entry.snapshot.lastUpdatedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Usage rows
            usageRow(title: entry.snapshot.session.windowType.displayName, usage: entry.snapshot.session)
            usageRow(title: entry.snapshot.opus.windowType.displayName, usage: entry.snapshot.opus)

            if let sonnet = entry.snapshot.sonnet {
                usageRow(title: sonnet.windowType.displayName, usage: sonnet)
            }

            Spacer()
        }
        .padding(4)
    }

    private func usageRow(title: String, usage: UsageWindow) -> some View {
        HStack(spacing: 12) {
            progressRing(for: usage)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Resets in \(usage.timeUntilReset)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(usage.percentUsed)%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(usage.status.color)
                Label(usage.status.label, systemImage: usage.status.icon)
                    .font(.caption2)
                    .foregroundStyle(usage.status.color)
            }
        }
        .padding(.vertical, 4)
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

#Preview(as: .systemLarge) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}
