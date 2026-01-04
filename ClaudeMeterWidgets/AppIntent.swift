//
//  AppIntent.swift
//  ClaudeMeterWidgets
//

import WidgetKit
import AppIntents

enum MetricType: String, AppEnum {
    case session
    case opus
    case sonnet

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .session: DisplayRepresentation(title: "Current session (5h)"),
        .opus: DisplayRepresentation(title: "All models (7d)"),
        .sonnet: DisplayRepresentation(title: "Sonnet (7d)")
    ]

    var displayName: String {
        switch self {
        case .session: return "Current session"
        case .opus: return "All models"
        case .sonnet: return "Sonnet"
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Metric"
    static var description = IntentDescription("Choose which usage metric to display")

    @Parameter(title: "Metric", default: .session)
    var metric: MetricType
}
