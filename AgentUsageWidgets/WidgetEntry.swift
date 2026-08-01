//
//  WidgetEntry.swift
//  AgentUsageWidgets
//

import Foundation
import WidgetKit
import AgentUsageKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    /// `nil` when neither CloudKit nor the App Group cache has a snapshot yet.
    /// The widget renders `WidgetNoDataView` rather than inventing numbers —
    /// a usage figure the user cannot act on is worse than an honest blank.
    let snapshot: UsageSnapshot?
    let metric: MetricType

    /// How old the Mac-published snapshot may be before the widget flags it.
    /// Sits just past one full reload cycle (30 min), so a healthy chain — Mac
    /// awake and publishing — never trips it, while a sleeping Mac shows up fast.
    private static let staleThreshold: TimeInterval = 45 * 60

    init(date: Date, snapshot: UsageSnapshot?, metric: MetricType = .session) {
        self.date = date
        self.snapshot = snapshot
        self.metric = metric
    }

    var selectedWindow: UsageWindow? {
        guard let snapshot else { return nil }
        let window: UsageWindow?
        switch metric {
        case .session:
            window = snapshot.session
        case .opus:
            window = snapshot.opus
        case .sonnet:
            window = snapshot.sonnet
        case .design:
            window = snapshot.design
        case .fable:
            window = snapshot.fable
        }
        guard let window, !window.isExpired(from: date) else { return nil }
        return window
    }

    /// Non-expired windows in the same order as the iOS provider card.
    var availableWindows: [UsageWindow] {
        guard let snapshot else { return [] }
        return [snapshot.session, snapshot.opus, snapshot.sonnet, snapshot.design, snapshot.fable]
            .compactMap { $0 }
            .filter { !$0.isExpired(from: date) }
    }

    /// Why a selected or summary presentation has no trustworthy value.
    var unavailableReason: WidgetUnavailableReason {
        guard let snapshot else { return .noData }

        let configuredWindow: UsageWindow?
        switch metric {
        case .session: configuredWindow = snapshot.session
        case .opus: configuredWindow = snapshot.opus
        case .sonnet: configuredWindow = snapshot.sonnet
        case .design: configuredWindow = snapshot.design
        case .fable: configuredWindow = snapshot.fable
        }

        guard let configuredWindow else { return .metricUnavailable }
        return configuredWindow.isExpired(from: date) ? .awaitingRefresh : .noData
    }

    /// Relative age of the data, measured from this entry's render time rather
    /// than `Date()` — every entry in a timeline is rendered up front.
    var lastUpdatedDescription: String {
        snapshot?.lastUpdatedDescription(asOf: date) ?? "never"
    }

    /// The Mac has not published in a while, so the numbers on screen are frozen
    /// rather than simply unchanged. Never true without a snapshot: the no-data
    /// state already says the widget is empty, so flagging it stale as well
    /// would double up on the same message.
    var isStale: Bool {
        guard let snapshot else { return false }
        return snapshot.age(asOf: date) > Self.staleThreshold
    }
}

enum WidgetUnavailableReason {
    case noData
    case metricUnavailable
    case awaitingRefresh
}
