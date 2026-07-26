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

    var body: some View {
        if let usage = entry.selectedWindow {
            content(for: usage)
        } else {
            // WidgetNoDataView switches on the same family, so each accessory
            // shape gets its own empty treatment.
            WidgetNoDataView()
        }
    }

    @ViewBuilder
    private func content(for usage: UsageWindow) -> some View {
        switch family {
        case .accessoryCircular:
            circularView(for: usage)
        case .accessoryRectangular:
            rectangularView(for: usage)
        case .accessoryInline:
            inlineView(for: usage)
        default:
            circularView(for: usage)
        }
    }

    // MARK: - Circular (Watch-style ring)

    private func circularView(for usage: UsageWindow) -> some View {
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

    private func rectangularView(for usage: UsageWindow) -> some View {
        // Derived from the entry's date, not `Date()` — WidgetKit renders every
        // entry of a timeline up front.
        let resetText = usage.resetDescription(from: entry.date)

        return VStack(alignment: .leading, spacing: 2) {
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

    private func inlineView(for usage: UsageWindow) -> some View {
        Text("\(entry.metric.displayName): \(usage.percentUsed)%")
            .accessibilityLabel("\(entry.metric.displayName) usage \(usage.percentUsed) percent")
    }
}

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview("Rectangular", as: .accessoryRectangular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview("Inline", as: .accessoryInline) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}
#endif
