//
//  WidgetEntry.swift
//  ClaudeMeterWidgets
//

import WidgetKit
import ClaudeMeterKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let metric: MetricType

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
        }
    }
}
