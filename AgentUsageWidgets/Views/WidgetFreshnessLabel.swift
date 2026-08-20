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
    var fetchedAt: Date?
    var font: Font = .caption2

    init(entry: WidgetEntry, fetchedAt: Date? = nil, font: Font = .caption2) {
        self.entry = entry
        self.fetchedAt = fetchedAt
        self.font = font
    }

    private var resolvedFetchedAt: Date? {
        fetchedAt ?? entry.providerSnapshot?.fetchedAt
    }

    private var isStale: Bool {
        entry.isStale(fetchedAt: resolvedFetchedAt)
    }

    private var lastUpdated: String {
        entry.lastUpdatedDescription(for: resolvedFetchedAt)
    }

    var body: some View {
        HStack(spacing: 3) {
            if isStale {
                Image(systemName: "clock.arrow.circlepath")
            }
            Text("Updated \(lastUpdated)")
        }
        .font(font)
        .foregroundStyle(
            isStale
                ? AnyShapeStyle(UsageStatus.warning.color)
                : AnyShapeStyle(.secondary)
        )
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isStale ? "Showing stale data" : "Last updated")
        .accessibilityValue("Updated \(lastUpdated)")
    }
}
