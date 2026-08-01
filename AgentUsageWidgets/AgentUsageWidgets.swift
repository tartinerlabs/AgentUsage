//
//  AgentUsageWidgets.swift
//  AgentUsageWidgets
//

import WidgetKit
import SwiftUI
import AgentUsageKit

// MARK: - Home Screen Widget

struct AgentUsageWidgets: Widget {
    let kind: String = "AgentUsageWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            AgentUsageWidgetsEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetProviderBackground(provider: WidgetDesign.provider)
                }
        }
        .configurationDisplayName("Claude Usage")
        .description("Track Claude usage windows at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AgentUsageWidgetsEntryView: View {
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

struct AgentUsageLockScreenWidget: Widget {
    let kind: String = "AgentUsageLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: LockScreenProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Check a Claude usage window at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews
//
// Each timeline pairs the populated state with the no-data state so the empty
// case stays visible during design work rather than only appearing on a fresh
// install.

#if DEBUG
#Preview(as: .systemSmall) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview(as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview(as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview(as: .accessoryCircular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}

#Preview(as: .accessoryRectangular) {
    AgentUsageLockScreenWidget()
} timeline: {
    WidgetEntry.preview()
    WidgetEntry.previewNoData()
}
#endif
