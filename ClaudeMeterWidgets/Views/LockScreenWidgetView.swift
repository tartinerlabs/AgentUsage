//
//  LockScreenWidgetView.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import ClaudeMeterKit
import WidgetKit

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    private var usage: UsageWindow {
        entry.selectedWindow
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular (Watch-style ring)

    private var circularView: some View {
        Gauge(value: usage.normalized) {
            Text(entry.metric.displayName.prefix(1))
                .font(.caption2)
                .fontWeight(.bold)
        } currentValueLabel: {
            Text("\(usage.percentUsed)")
                .font(.system(.body, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("\(entry.metric.displayName) usage")
        .accessibilityValue("\(usage.percentUsed) percent")
    }

    // MARK: - Rectangular (Bar with text)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.metric.displayName)
                    .font(.headline)
                Spacer()
                Text("\(usage.percentUsed)%")
                    .font(.headline)
                    .fontWeight(.bold)
                if usage.isUsingExtraUsage {
                    Text("Extra")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }

            Gauge(value: usage.normalized) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)

            Text("Resets in \(usage.timeUntilReset)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.metric.displayName) usage")
        .accessibilityValue("\(usage.percentUsed) percent, resets in \(usage.timeUntilReset)")
    }

    // MARK: - Inline (Single line text)

    private var inlineView: some View {
        Text("\(entry.metric.displayName): \(usage.percentUsed)%")
            .accessibilityLabel("\(entry.metric.displayName) usage \(usage.percentUsed) percent")
    }
}

#Preview(as: .accessoryCircular) {
    ClaudeMeterLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryRectangular) {
    ClaudeMeterLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryInline) {
    ClaudeMeterLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}
