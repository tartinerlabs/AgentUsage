//
//  WidgetFreshnessLabel.swift
//  AgentUsageWidgets
//
//  Mirrors the app's `LastUpdatedLabel`: a compact "Updated X ago" that turns
//  orange with a clock glyph once the data is stale. Widgets have no live view
//  model to tell them they are offline, so staleness is derived purely from how
//  long ago the Mac published the snapshot.
//

import AgentUsageKit
import SwiftUI

struct WidgetFreshnessLabel: View {
    let entry: WidgetEntry
    var font: Font = .caption2

    var body: some View {
        HStack(spacing: 3) {
            if entry.isStale {
                Image(systemName: "clock.arrow.circlepath")
            }
            Text("Updated \(entry.lastUpdatedDescription)")
        }
        .font(font)
        .foregroundStyle(
            entry.isStale
                ? AnyShapeStyle(UsageStatus.warning.color)
                : AnyShapeStyle(.secondary)
        )
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isStale ? "Showing stale data" : "Last updated")
        .accessibilityValue("Updated \(entry.lastUpdatedDescription)")
    }
}
