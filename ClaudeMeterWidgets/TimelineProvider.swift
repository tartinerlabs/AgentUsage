//
//  TimelineProvider.swift
//  ClaudeMeterWidgets
//

import WidgetKit
import ClaudeMeterKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> WidgetEntry {
        let snapshot = WidgetDataManager.load() ?? .placeholder
        return WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let snapshot = WidgetDataManager.load() ?? .placeholder
        let entry = WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)

        // Request refresh every 15 minutes
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
        let snapshot = WidgetDataManager.load() ?? .placeholder
        let entry = WidgetEntry(date: .now, snapshot: snapshot, metric: configuration.metric)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
