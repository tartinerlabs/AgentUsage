//
//  ClaudeMeterWidgets.swift
//  ClaudeMeterWidgets
//

import WidgetKit
import SwiftUI

// MARK: - Home Screen Widget

struct ClaudeMeterWidgets: Widget {
    let kind: String = "ClaudeMeterWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            ClaudeMeterWidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Monitor your Claude API usage limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClaudeMeterWidgetsEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Lock Screen Widget

struct ClaudeMeterLockScreenWidget: Widget {
    let kind: String = "ClaudeMeterLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: LockScreenProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Quick glance at your Claude usage.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .systemMedium) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .systemLarge) {
    ClaudeMeterWidgets()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryCircular) {
    ClaudeMeterLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}

#Preview(as: .accessoryRectangular) {
    ClaudeMeterLockScreenWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .placeholder, metric: .session)
}
