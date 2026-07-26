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
        switch metric {
        case .session:
            return snapshot.session
        case .opus:
            return snapshot.opus
        case .sonnet:
            return snapshot.sonnet ?? snapshot.opus
        case .design:
            return snapshot.design ?? snapshot.opus
        case .fable:
            return snapshot.fable ?? snapshot.opus
        }
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
