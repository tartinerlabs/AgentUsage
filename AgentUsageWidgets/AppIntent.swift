//
//  AppIntent.swift
//  AgentUsageWidgets
//

import AgentUsageKit
import AppIntents
import Foundation
import WidgetKit

/// Legacy Claude configuration values retained so existing widgets keep their
/// selected window. The parameter is omitted from `parameterSummary`, so new
/// configuration sheets expose only the provider-neutral entity picker.
enum MetricType: String, AppEnum {
    case session
    case opus
    case sonnet
    case design
    case fable

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .session: DisplayRepresentation(title: "Current session (5h)"),
        .opus: DisplayRepresentation(title: "All models (7d)"),
        .sonnet: DisplayRepresentation(title: "Sonnet (7d)"),
        .design: DisplayRepresentation(title: "Claude Design (7d)"),
        .fable: DisplayRepresentation(title: "Fable (7d)"),
    ]
}

/// A provider/window pair offered in the widget configuration sheet.
///
/// The identifier includes the provider because providers may use the same
/// window ID. The remaining fields let WidgetKit preserve the selection without
/// reducing dynamic Cursor windows to `UsageWindowType.custom`.
struct WidgetUsageWindowEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Usage Window")
    static var defaultQuery = WidgetUsageWindowQuery()

    let id: String
    let providerRawValue: String
    let windowIDRawValue: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(provider?.displayName ?? "Unknown provider")"
        )
    }

    var provider: AgentUsageKit.Provider? {
        AgentUsageKit.Provider(rawValue: providerRawValue)
    }

    var selection: UsageActivitySelection? {
        guard let provider else { return nil }
        return UsageActivitySelection(
            provider: provider,
            windowID: UsageWindowID(rawValue: windowIDRawValue)
        )
    }

    init(provider: AgentUsageKit.Provider, window: UsageWindow) {
        id = Self.identifier(provider: provider, windowID: window.windowID)
        providerRawValue = provider.rawValue
        windowIDRawValue = window.windowID.rawValue
        displayName = window.displayName
    }

    /// Rebuild enough identity to preserve an existing configuration when its
    /// provider cache is temporarily absent. The real display name replaces this
    /// fallback as soon as the next provider snapshot arrives.
    init?(identifier: String) {
        guard let separator = identifier.firstIndex(of: "/") else { return nil }
        let providerValue = String(identifier[..<separator])
        let windowValue = String(identifier[identifier.index(after: separator)...])
        guard AgentUsageKit.Provider(rawValue: providerValue) != nil,
              !windowValue.isEmpty else {
            return nil
        }

        id = identifier
        providerRawValue = providerValue
        windowIDRawValue = windowValue
        displayName = UsageWindowType(rawValue: windowValue)?.displayName ?? "Usage"
    }

    private static func identifier(
        provider: AgentUsageKit.Provider,
        windowID: UsageWindowID
    ) -> String {
        "\(provider.rawValue)/\(windowID.rawValue)"
    }
}

struct WidgetUsageWindowQuery: EntityQuery {
    /// Only providers currently wired by the app are configurable. OpenCode's
    /// services remain deliberately disabled even though its model types exist.
    private static let supportedProviders: Set<AgentUsageKit.Provider> = [
        .claude,
        .codex,
        .cursor,
    ]

    func entities(for identifiers: [WidgetUsageWindowEntity.ID]) async throws -> [WidgetUsageWindowEntity] {
        let knownEntities = Dictionary(
            uniqueKeysWithValues: entities(includeExpired: true).map { ($0.id, $0) }
        )
        return identifiers.compactMap { identifier in
            if let known = knownEntities[identifier] { return known }
            guard let fallback = WidgetUsageWindowEntity(identifier: identifier),
                  let provider = fallback.provider,
                  Self.supportedProviders.contains(provider) else {
                return nil
            }
            return fallback
        }
    }

    func suggestedEntities() async throws -> [WidgetUsageWindowEntity] {
        let snapshots = await WidgetTimelineLoader.currentSnapshots()
        return entities(in: snapshots, includeExpired: false)
    }

    private func entities(
        in snapshots: [ProviderUsageSnapshot]? = nil,
        includeExpired: Bool
    ) -> [WidgetUsageWindowEntity] {
        let now = Date()
        let providerSnapshots = snapshots ?? WidgetDataStorage.shared.loadProviderSnapshots()
        return providerSnapshots.flatMap {
            snapshot -> [WidgetUsageWindowEntity] in
            guard Self.supportedProviders.contains(snapshot.provider) else { return [] }
            return snapshot.windows
                .filter { includeExpired || !$0.isExpired(from: now) }
                .map { WidgetUsageWindowEntity(provider: snapshot.provider, window: $0) }
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Usage Window"
    static var description = IntentDescription(
        "Choose a provider usage window to display. Larger widgets show the other windows for that provider too."
    )

    /// Kept under its original property name and raw enum values so WidgetKit can
    /// decode configurations created by earlier app versions.
    @Parameter(title: "Legacy Claude Metric", default: .session)
    var metric: MetricType

    /// Optional so a widget can be added before the Mac has published data. The
    /// stable legacy Claude selection is used until a provider window is chosen.
    @Parameter(title: "Usage Window")
    var usageWindow: WidgetUsageWindowEntity?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$usageWindow
        }
    }

    var selection: UsageActivitySelection {
        usageWindow?.selection
            ?? UsageActivitySelection(
                provider: .claude,
                windowID: UsageWindowID(rawValue: metric.rawValue)
            )
    }
}
