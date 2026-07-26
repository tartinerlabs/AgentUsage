//
//  LockScreenWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    private var usage: UsageWindow {
        entry.selectedWindow
    }

    /// Derived from the entry's date, not `Date()` — WidgetKit renders every
    /// entry of a timeline up front.
    private var resetText: String {
        usage.resetDescription(from: entry.date)
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
                // Accessory families render monochrome, so staleness is a glyph
                // rather than the orange label the home-screen widgets use.
                if entry.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                }
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

            Text(entry.isStale ? "Updated \(entry.lastUpdatedDescription)" : resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.metric.displayName) usage")
        .accessibilityValue(
            entry.isStale
                ? "\(usage.percentUsed) percent, stale, updated \(entry.lastUpdatedDescription)"
                : "\(usage.percentUsed) percent, \(resetText.lowercased())"
        )
    }

    // MARK: - Inline (Single line text)

    private var inlineView: some View {
        Text("\(entry.metric.displayName): \(usage.percentUsed)%")
            .accessibilityLabel("\(entry.metric.displayName) usage \(usage.percentUsed) percent")
    }
}

#Preview(as: .accessoryCircular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryRectangular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryInline) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}
