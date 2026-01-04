//
//  SmallWidgetView.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import ClaudeMeterKit
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    private var usage: UsageWindow {
        entry.selectedWindow
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(entry.metric.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            progressRing
                .frame(width: 70, height: 70)

            Text("\(usage.percentUsed)%")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(usage.status.color)

            Text("Resets \(usage.timeUntilReset)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: usage.normalized)
                .stroke(
                    usage.status.color,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview(as: .systemSmall) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .opus)
}
