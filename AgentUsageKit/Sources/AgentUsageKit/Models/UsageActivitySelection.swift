//
//  UsageActivitySelection.swift
//  AgentUsageKit
//
//  Stable provider/window identity for widgets and Live Activities.
//

import Foundation

/// Identifies the exact provider rate window tracked by a widget or Live Activity.
///
/// The provider is part of the identity because different providers may use the
/// same window identifier (for example, `session`).
public struct UsageActivitySelection: Sendable, Codable, Hashable {
    public let provider: Provider
    public let windowID: UsageWindowID

    public init(provider: Provider, windowID: UsageWindowID) {
        self.provider = provider
        self.windowID = windowID
    }

    /// The most urgent live window across every provider snapshot.
    ///
    /// Unconfigured Small and Lock Screen widgets use this instead of a
    /// Claude-first fallback. Urgency is worst `UsageStatus`, then higher
    /// utilization, then sooner reset. Canonical `Provider` order breaks ties.
    public static func mostUrgent(
        in snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> UsageActivitySelection? {
        glanceWindows(in: snapshots, preferring: nil, now: now)
            .max { lhs, rhs in
                if lhs.window.isLessUrgent(than: rhs.window, now: now) { return true }
                if rhs.window.isLessUrgent(than: lhs.window, now: now) { return false }
                return lhs.provider.sortIndex > rhs.provider.sortIndex
            }
            .map { UsageActivitySelection(provider: $0.provider, windowID: $0.window.windowID) }
    }

    /// One live window per provider that currently has quota data, most recently
    /// used first. A configured selection wins for that provider only.
    public static func glanceWindows(
        in snapshots: [ProviderUsageSnapshot],
        preferring selection: UsageActivitySelection?,
        now: Date
    ) -> [WidgetGlanceWindow] {
        let glances = Provider.allCases.compactMap { provider -> WidgetGlanceWindow? in
            guard let snapshot = snapshots.first(where: { $0.provider == provider }),
                  let window = snapshot.primaryWindow(preferring: selection, now: now) else {
                return nil
            }
            return WidgetGlanceWindow(
                provider: provider,
                window: window,
                fetchedAt: snapshot.fetchedAt,
                lastUsedAt: snapshot.lastUsedAt
            )
        }
        return glances.sorted { lhs, rhs in
            precedesByRecency(
                lhsUsedAt: lhs.lastUsedAt,
                lhsWindow: lhs.window,
                lhsProvider: lhs.provider,
                rhsUsedAt: rhs.lastUsedAt,
                rhsWindow: rhs.window,
                rhsProvider: rhs.provider
            )
        }
    }

    /// Snapshots ordered by newest local activity, then hottest live window.
    /// Unknown `lastUsedAt` sorts last among recency; no live window sorts last
    /// among that group. Canonical `Provider` order is the final tie-break.
    public static func sortedByRecency(
        _ snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> [ProviderUsageSnapshot] {
        snapshots.sorted { lhs, rhs in
            precedesByRecency(
                lhsUsedAt: lhs.lastUsedAt,
                lhsWindow: lhs.hottestLiveWindow(now: now),
                lhsProvider: lhs.provider,
                rhsUsedAt: rhs.lastUsedAt,
                rhsWindow: rhs.hottestLiveWindow(now: now),
                rhsProvider: rhs.provider
            )
        }
    }

    /// `true` when `lhs` should appear before `rhs`.
    ///
    /// Newest `lastUsedAt` wins. Equal or missing timestamps fall through to
    /// higher live utilization, then sooner reset, then canonical provider order.
    /// Pace-based `UsageStatus` is not a list key — it is what used to reshuffle
    /// a barely-started window above a high-% short window.
    public static func precedesByRecency(
        lhsUsedAt: Date?,
        lhsWindow: UsageWindow? = nil,
        lhsProvider: Provider,
        rhsUsedAt: Date?,
        rhsWindow: UsageWindow? = nil,
        rhsProvider: Provider
    ) -> Bool {
        switch (lhsUsedAt, rhsUsedAt) {
        case (let left?, let right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        return precedesByUtilization(
            lhsWindow: lhsWindow,
            lhsProvider: lhsProvider,
            rhsWindow: rhsWindow,
            rhsProvider: rhsProvider
        )
    }

    /// Higher live utilization first, then sooner reset. No live window sorts last.
    private static func precedesByUtilization(
        lhsWindow: UsageWindow?,
        lhsProvider: Provider,
        rhsWindow: UsageWindow?,
        rhsProvider: Provider
    ) -> Bool {
        switch (lhsWindow, rhsWindow) {
        case (let left?, let right?):
            if left.utilization != right.utilization {
                return left.utilization > right.utilization
            }
            if left.resetsAt != right.resetsAt {
                return left.resetsAt < right.resetsAt
            }
            return lhsProvider.sortIndex < rhsProvider.sortIndex
        case (nil, nil):
            return lhsProvider.sortIndex < rhsProvider.sortIndex
        case (nil, _):
            return false
        case (_, nil):
            return true
        }
    }

    /// Snapshots ordered by live `primaryWindow` urgency. No live window sorts last;
    /// equal urgency uses canonical `Provider` order.
    public static func sortedByUrgency(
        _ snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> [ProviderUsageSnapshot] {
        snapshots.sorted { lhs, rhs in
            precedesByUrgency(
                lhsWindow: lhs.primaryWindow(now: now),
                lhsProvider: lhs.provider,
                rhsWindow: rhs.primaryWindow(now: now),
                rhsProvider: rhs.provider,
                now: now
            )
        }
    }

    /// `true` when `lhs` should appear before `rhs` (more urgent first).
    private static func precedesByUrgency(
        lhsWindow: UsageWindow?,
        lhsProvider: Provider,
        rhsWindow: UsageWindow?,
        rhsProvider: Provider,
        now: Date
    ) -> Bool {
        switch (lhsWindow, rhsWindow) {
        case (let left?, let right?):
            if left.isLessUrgent(than: right, now: now) { return false }
            if right.isLessUrgent(than: left, now: now) { return true }
            return lhsProvider.sortIndex < rhsProvider.sortIndex
        case (nil, nil):
            return lhsProvider.sortIndex < rhsProvider.sortIndex
        case (nil, _):
            return false
        case (_, nil):
            return true
        }
    }
}

/// One provider's glance row for Medium and Large widgets.
public struct WidgetGlanceWindow: Sendable, Identifiable {
    public let provider: Provider
    public let window: UsageWindow
    public let fetchedAt: Date
    public let lastUsedAt: Date?

    public var id: String { provider.rawValue }

    public init(
        provider: Provider,
        window: UsageWindow,
        fetchedAt: Date,
        lastUsedAt: Date? = nil
    ) {
        self.provider = provider
        self.window = window
        self.fetchedAt = fetchedAt
        self.lastUsedAt = lastUsedAt
    }
}

extension ProviderUsageSnapshot {
    /// Non-expired windows, preserving the snapshot's published order.
    public func liveWindows(now: Date) -> [UsageWindow] {
        windows.filter { !$0.isExpired(from: now) }
    }

    /// The window a glance row should show: the configured window when it is
    /// still live for this provider, otherwise the most urgent live window.
    public func primaryWindow(
        preferring selection: UsageActivitySelection? = nil,
        now: Date
    ) -> UsageWindow? {
        let live = liveWindows(now: now)
        if let selection, selection.provider == provider,
           let preferred = live.first(where: { $0.windowID == selection.windowID }) {
            return preferred
        }
        return live.max { $0.isLessUrgent(than: $1, now: now) }
    }

    /// Highest-utilization live window. Utilization ties prefer the sooner reset.
    public func hottestLiveWindow(now: Date) -> UsageWindow? {
        liveWindows(now: now).max { lhs, rhs in
            if lhs.utilization != rhs.utilization {
                return lhs.utilization < rhs.utilization
            }
            return lhs.resetsAt > rhs.resetsAt
        }
    }
}

extension UsageWindow {
    /// Status first, then utilization, then sooner reset. Equal windows compare as
    /// not-less-urgent so a caller can apply a separate provider-order tie-break.
    func isLessUrgent(than other: UsageWindow, now: Date) -> Bool {
        let ownStatus = status(from: now)
        let otherStatus = other.status(from: now)
        if ownStatus != otherStatus { return ownStatus < otherStatus }
        if utilization != other.utilization { return utilization < other.utilization }
        if resetsAt != other.resetsAt { return resetsAt > other.resetsAt }
        return false
    }
}

extension Provider {
    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}
