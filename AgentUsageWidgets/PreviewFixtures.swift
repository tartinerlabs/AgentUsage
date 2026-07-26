//
//  PreviewFixtures.swift
//  AgentUsageWidgets
//
//  Fabricated snapshots exist here and nowhere else.
//
//  This used to live on `UsageSnapshot.placeholder` in AgentUsageKit, where the
//  timeline provider reached for it whenever CloudKit and the App Group cache
//  were both empty — so a fresh install rendered invented percentages as if they
//  were real. Keeping the fixture in the widget target behind `#if DEBUG` means
//  a release binary contains no sample usage figures at all; the shipping
//  no-data path is `WidgetNoDataView`.
//
//  Everything below is `#if DEBUG` and must stay that way.
//

#if DEBUG
import Foundation
import AgentUsageKit

extension UsageSnapshot {
    /// Representative usage for Xcode canvas previews only.
    static var previewSample: UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            session: UsageWindow(
                utilization: 45,
                resetsAt: now.addingTimeInterval(2.5 * 60 * 60),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 32,
                resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                windowType: .opus
            ),
            sonnet: UsageWindow(
                utilization: 28,
                resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                windowType: .sonnet
            ),
            design: UsageWindow(
                utilization: 12,
                resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                windowType: .design
            ),
            fable: UsageWindow(
                utilization: 16,
                resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                windowType: .fable
            ),
            fetchedAt: now
        )
    }
}

extension WidgetEntry {
    /// A populated entry for previews.
    static func preview(metric: MetricType = .session) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: .previewSample, metric: metric)
    }

    /// The empty state as the shipping app produces it — no snapshot at all.
    static func previewNoData(metric: MetricType = .session) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: nil, metric: metric)
    }
}
#endif
