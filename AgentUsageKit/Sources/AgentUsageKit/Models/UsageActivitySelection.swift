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

    /// One live window per provider that currently has quota data, in canonical
    /// provider order. A configured selection wins for that provider only.
    public static func glanceWindows(
        in snapshots: [ProviderUsageSnapshot],
        preferring selection: UsageActivitySelection?,
        now: Date
    ) -> [WidgetGlanceWindow] {
        Provider.allCases.compactMap { provider in
            guard let snapshot = snapshots.first(where: { $0.provider == provider }),
                  let window = snapshot.primaryWindow(preferring: selection, now: now) else {
                return nil
            }
            return WidgetGlanceWindow(
                provider: provider,
                window: window,
                fetchedAt: snapshot.fetchedAt
            )
        }
    }
}

/// One provider's glance row for Medium and Large widgets.
public struct WidgetGlanceWindow: Sendable, Identifiable {
    public let provider: Provider
    public let window: UsageWindow
    public let fetchedAt: Date

    public var id: String { provider.rawValue }

    public init(provider: Provider, window: UsageWindow, fetchedAt: Date) {
        self.provider = provider
        self.window = window
        self.fetchedAt = fetchedAt
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
    fileprivate var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}
