//
//  TimelineProvider.swift
//  AgentUsageWidgets
//

import AgentUsageKit
import Foundation
import WidgetKit

/// Shared timeline construction for the home-screen and lock-screen widgets.
enum WidgetTimelineLoader {
    private static let fetchTimeout: Duration = .seconds(8)
    private static let entryStride: TimeInterval = 5 * 60
    private static let reloadInterval: TimeInterval = 30 * 60
    private static let entryHorizon: TimeInterval = 35 * 60

    /// Prefer the complete Mac-published CloudKit payload, then fall back to the
    /// provider-neutral App Group cache. A modern provider-only record must not
    /// be combined with an older cached snapshot.
    static func currentSnapshots() async -> [ProviderUsageSnapshot] {
        if let synced = await syncedPayload() {
            WidgetDataStorage.shared.save(synced)
            return synced.providerSnapshots
        }
        return WidgetDataManager.load()
    }

    static func timeline(
        snapshots: [ProviderUsageSnapshot],
        selection: UsageActivitySelection?,
        from now: Date = .now
    ) -> Timeline<WidgetEntry> {
        let entries = stride(from: 0, through: entryHorizon, by: entryStride).map { offset in
            WidgetEntry(
                date: now.addingTimeInterval(offset),
                snapshots: snapshots,
                selection: selection
            )
        }
        return Timeline(
            entries: entries,
            policy: .after(now.addingTimeInterval(reloadInterval))
        )
    }

    private static func syncedPayload() async -> WidgetUsagePayload? {
        await withTaskGroup(of: WidgetUsagePayload?.self) { group in
            group.addTask {
                guard let synced = await UsageSyncService.shared.fetchLatest() else { return nil }
                return WidgetUsagePayload(
                    snapshot: synced.snapshot,
                    providerSnapshots: synced.providerSnapshots
                )
            }
            group.addTask {
                try? await Task.sleep(for: fetchTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

struct HomeScreenTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshots: WidgetDataManager.load())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        WidgetEntry(
            date: .now,
            snapshots: WidgetDataManager.load(),
            selection: configuration.selection
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let snapshots = await WidgetTimelineLoader.currentSnapshots()
        return WidgetTimelineLoader.timeline(
            snapshots: snapshots,
            selection: configuration.selection
        )
    }
}

struct LockScreenTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshots: WidgetDataManager.load())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        WidgetEntry(
            date: .now,
            snapshots: WidgetDataManager.load(),
            selection: configuration.selection
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let snapshots = await WidgetTimelineLoader.currentSnapshots()
        return WidgetTimelineLoader.timeline(
            snapshots: snapshots,
            selection: configuration.selection
        )
    }
}
