//
//  WidgetEntry.swift
//  AgentUsageWidgets
//

import AgentUsageKit
import Foundation
import WidgetKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let provider: AgentUsageKit.Provider
    let providerSnapshot: ProviderUsageSnapshot?
    let selection: UsageActivitySelection?

    /// How old the selected provider's snapshot may be before the widget flags it.
    private static let staleThreshold: TimeInterval = 45 * 60

    private static let supportedProviders: [AgentUsageKit.Provider] = [
        .claude,
        .codex,
        .cursor,
    ]

    init(
        date: Date,
        snapshots: [ProviderUsageSnapshot],
        selection: UsageActivitySelection? = nil
    ) {
        self.date = date
        let resolvedSelection = selection ?? Self.defaultSelection(in: snapshots)
        let resolvedProvider = resolvedSelection?.provider ?? .claude
        self.selection = resolvedSelection
        provider = resolvedProvider
        providerSnapshot = snapshots.first { $0.provider == resolvedProvider }
    }

    var selectedWindow: UsageWindow? {
        guard let providerSnapshot, let selection else { return nil }
        guard let window = providerSnapshot.windows.first(where: { $0.windowID == selection.windowID }),
              !window.isExpired(from: date) else {
            return nil
        }
        return window
    }

    /// Non-expired windows in the provider's published order.
    var availableWindows: [UsageWindow] {
        providerSnapshot?.windows.filter { !$0.isExpired(from: date) } ?? []
    }

    /// Why a selected or summary presentation has no trustworthy value.
    var unavailableReason: WidgetUnavailableReason {
        guard let providerSnapshot else { return .noData }
        guard let selection,
              let configuredWindow = providerSnapshot.windows.first(where: { $0.windowID == selection.windowID }) else {
            return providerSnapshot.windows.isEmpty ? .noData : .windowUnavailable
        }
        return configuredWindow.isExpired(from: date) ? .awaitingRefresh : .noData
    }

    var lastUpdatedDescription: String {
        guard let providerSnapshot else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: providerSnapshot.fetchedAt, relativeTo: date)
    }

    var isStale: Bool {
        guard let providerSnapshot else { return false }
        return date.timeIntervalSince(providerSnapshot.fetchedAt) > Self.staleThreshold
    }

    private static func defaultSelection(
        in snapshots: [ProviderUsageSnapshot]
    ) -> UsageActivitySelection? {
        if let claude = snapshots.first(where: { $0.provider == .claude }),
           let window = claude.windows.first(where: { $0.windowID.rawValue == UsageWindowType.session.rawValue })
            ?? claude.windows.first {
            return UsageActivitySelection(provider: .claude, windowID: window.windowID)
        }

        for provider in supportedProviders where provider != .claude {
            guard let snapshot = snapshots.first(where: { $0.provider == provider }),
                  let window = snapshot.windows.first else {
                continue
            }
            return UsageActivitySelection(provider: provider, windowID: window.windowID)
        }
        return nil
    }
}

enum WidgetUnavailableReason {
    case noData
    case windowUnavailable
    case awaitingRefresh
}
