//
//  TimelineProvider.swift
//  AgentUsageWidgets
//

import Foundation
import WidgetKit
import AgentUsageKit

/// Shared timeline construction for the home-screen and lock-screen widgets.
///
/// The widget reads the snapshot macOS publishes to CloudKit rather than calling
/// a provider API. That keeps the per-account rate limit safe (only the Mac talks
/// to `/api/oauth/usage`) while making widget freshness independent of whether the
/// iOS app has been launched — the App Group cache alone only ever changes when
/// the app process runs, which is why widgets appeared to stop refreshing.
enum WidgetTimelineLoader {
    /// How long the widget waits for CloudKit before falling back to the cache.
    /// Timeline providers are killed if they take too long, so bound the fetch.
    private static let fetchTimeout: Duration = .seconds(8)

    /// Spacing between pre-rendered entries within one timeline.
    private static let entryStride: TimeInterval = 5 * 60

    /// When WidgetKit should build the next timeline (and re-read CloudKit).
    private static let reloadInterval: TimeInterval = 30 * 60

    /// Entries are emitted slightly past `reloadInterval` so a delayed reload does
    /// not leave the widget rendering the final entry indefinitely.
    private static let entryHorizon: TimeInterval = 35 * 60

    /// The freshest snapshot available, preferring the Mac's CloudKit record and
    /// falling back to the App Group cache when iCloud is unavailable or empty.
    ///
    /// Returns `nil` when neither source has anything. The widget then renders
    /// its no-data state rather than a fabricated one — showing invented
    /// percentages here would be indistinguishable from real usage.
    static func currentSnapshot() async -> UsageSnapshot? {
        if let synced = await syncedSnapshot() {
            // Cache it so the synchronous `placeholder`/`snapshot` paths render
            // real data instantly and the widget survives an offline reload.
            WidgetDataStorage.shared.save(synced)
            return synced
        }
        return WidgetDataManager.load()
    }

    /// One entry every `entryStride` so reset countdowns and pace-based status
    /// advance between reloads. WidgetKit renders every entry when the timeline is
    /// built, so each view must derive time-dependent values from `entry.date`
    /// rather than `Date()`.
    static func timeline(
        snapshot: UsageSnapshot?,
        metric: MetricType,
        from now: Date = .now
    ) -> Timeline<WidgetEntry> {
        let entries = stride(from: 0, through: entryHorizon, by: entryStride).map { offset in
            WidgetEntry(
                date: now.addingTimeInterval(offset),
                snapshot: snapshot,
                metric: metric
            )
        }
        return Timeline(
            entries: entries,
            policy: .after(now.addingTimeInterval(reloadInterval))
        )
    }

    /// `fetchLatest()` already swallows CloudKit errors, but it can still stall on a
    /// bad network. Race it against a timeout so the provider always returns.
    private static func syncedSnapshot() async -> UsageSnapshot? {
        await withTaskGroup(of: UsageSnapshot?.self) { group in
            group.addTask {
                await UsageSyncService.shared.fetchLatest()?.snapshot
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

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        // Synchronous, so the cache is the only source available here. Real
        // cached numbers when we have them, an honest blank when we don't.
        WidgetEntry(date: .now, snapshot: WidgetDataManager.load())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        // The gallery/transient preview should be instant, so read the cache only.
        WidgetEntry(date: .now, snapshot: WidgetDataManager.load(), metric: configuration.metric)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let snapshot = await WidgetTimelineLoader.currentSnapshot()
        return WidgetTimelineLoader.timeline(snapshot: snapshot, metric: configuration.metric)
    }
}

struct LockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        // Synchronous, so the cache is the only source available here. Real
        // cached numbers when we have them, an honest blank when we don't.
        WidgetEntry(date: .now, snapshot: WidgetDataManager.load())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: WidgetDataManager.load(), metric: configuration.metric)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let snapshot = await WidgetTimelineLoader.currentSnapshot()
        return WidgetTimelineLoader.timeline(snapshot: snapshot, metric: configuration.metric)
    }
}
