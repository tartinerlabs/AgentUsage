//
//  WidgetEntry.swift
//  AgentUsageWidgets
//

import Foundation
import WidgetKit
import AgentUsageKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let metric: MetricType

    /// How old the Mac-published snapshot may be before the widget flags it.
    /// Sits just past one full reload cycle (30 min), so a healthy chain — Mac
    /// awake and publishing — never trips it, while a sleeping Mac shows up fast.
    private static let staleThreshold: TimeInterval = 45 * 60

    init(date: Date, snapshot: UsageSnapshot, metric: MetricType = .session) {
        self.date = date
        self.snapshot = snapshot
        self.metric = metric
    }

    var selectedWindow: UsageWindow {
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
        snapshot.lastUpdatedDescription(asOf: date)
    }

    /// The Mac has not published in a while, so the numbers on screen are frozen
    /// rather than simply unchanged.
    var isStale: Bool {
        snapshot.age(asOf: date) > Self.staleThreshold
    }
}
