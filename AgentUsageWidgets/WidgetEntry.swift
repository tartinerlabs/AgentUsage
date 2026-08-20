//
//  WidgetEntry.swift
//  AgentUsageWidgets
//

import AgentUsageKit
import Foundation
import WidgetKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [ProviderUsageSnapshot]
    let provider: AgentUsageKit.Provider?
    let providerSnapshot: ProviderUsageSnapshot?
    let selection: UsageActivitySelection?

    /// How old a snapshot may be before the widget flags it.
    private static let staleThreshold: TimeInterval = 45 * 60

    init(
        date: Date,
        snapshots: [ProviderUsageSnapshot],
        selection: UsageActivitySelection? = nil
    ) {
        self.date = date
        self.snapshots = snapshots
        let resolvedSelection = selection
            ?? UsageActivitySelection.mostUrgent(in: snapshots, now: date)
        self.selection = resolvedSelection
        provider = resolvedSelection?.provider
        providerSnapshot = resolvedSelection.flatMap { resolved in
            snapshots.first { $0.provider == resolved.provider }
        }
    }

    var selectedWindow: UsageWindow? {
        guard let providerSnapshot, let selection else { return nil }
        guard let window = providerSnapshot.windows.first(where: { $0.windowID == selection.windowID }),
              !window.isExpired(from: date) else {
            return nil
        }
        return window
    }

    /// Non-expired windows for a specific provider, in published order.
    func liveWindows(for provider: AgentUsageKit.Provider?) -> [UsageWindow] {
        guard let provider else { return [] }
        return snapshots.first { $0.provider == provider }?.liveWindows(now: date) ?? []
    }

    /// One live window per provider with quota data, in canonical provider order.
    var glanceWindows: [WidgetGlanceWindow] {
        UsageActivitySelection.glanceWindows(
            in: snapshots,
            preferring: selection,
            now: date
        )
    }

    /// Why a selected or summary presentation has no trustworthy value.
    var unavailableReason: WidgetUnavailableReason {
        if let selection {
            guard let providerSnapshot else { return .noData }
            guard let configuredWindow = providerSnapshot.windows.first(where: { $0.windowID == selection.windowID }) else {
                return providerSnapshot.windows.isEmpty ? .noData : .windowUnavailable
            }
            return configuredWindow.isExpired(from: date) ? .awaitingRefresh : .noData
        }

        let hasExpiredWindow = snapshots.contains { snapshot in
            snapshot.windows.contains { $0.isExpired(from: date) }
        }
        return hasExpiredWindow ? .awaitingRefresh : .noData
    }

    var lastUpdatedDescription: String {
        lastUpdatedDescription(for: providerSnapshot?.fetchedAt)
    }

    var isStale: Bool {
        isStale(fetchedAt: providerSnapshot?.fetchedAt)
    }

    func lastUpdatedDescription(for fetchedAt: Date?) -> String {
        guard let fetchedAt else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: date)
    }

    func isStale(fetchedAt: Date?) -> Bool {
        guard let fetchedAt else { return false }
        return date.timeIntervalSince(fetchedAt) > Self.staleThreshold
    }
}

enum WidgetUnavailableReason {
    case noData
    case windowUnavailable
    case awaitingRefresh
}
