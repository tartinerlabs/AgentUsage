//
//  TimelineProvider.swift
//  AgentUsageWidgets
//

import WidgetKit
import AgentUsageKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        let snapshot = WidgetDataManager.load() ?? .placeholder
        return WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        // Read only the shared snapshot the app writes (sourced from the Mac via
        // CloudKit). The widget no longer calls the Claude API itself — doing so
        // per widget multiplied requests and contributed to rate limiting.
        let snapshot = WidgetDataManager.load() ?? .placeholder
        let entry = WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)

        // Re-render periodically to keep reset countdowns current.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

struct LockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        let snapshot = WidgetDataManager.load() ?? .placeholder
        return WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        // Read only the shared snapshot; see `Provider.timeline` above.
        let snapshot = WidgetDataManager.load() ?? .placeholder
        let entry = WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
