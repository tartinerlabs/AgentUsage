//
//  WidgetDataManager.swift
//  AgentUsage
//
//  iOS app's widget data manager with WidgetKit integration
//  Uses AgentUsageKit's WidgetDataStorage for data persistence
//

#if os(iOS)
import Foundation
import AgentUsageKit
import OSLog
import WidgetKit

/// Manages shared data between the main app and widget extension via App Groups
/// Adds WidgetKit-specific functionality (timeline refresh) on top of shared storage
actor WidgetDataManager: WidgetDataServiceProtocol {
    static let shared = WidgetDataManager()

    private init() {}

    /// Save all provider snapshots to shared storage and reload widget timelines.
    func save(_ snapshots: [ProviderUsageSnapshot]) {
        if WidgetDataStorage.shared.save(snapshots) {
            Logger.widget.debug("Saved provider snapshots to App Groups")
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            Logger.widget.error("Failed to save provider snapshots")
        }
    }

    /// Load provider snapshots from shared storage.
    nonisolated func load() -> [ProviderUsageSnapshot] {
        WidgetDataStorage.shared.loadProviderSnapshots()
    }

    /// Clear cached data and reload widget timelines
    func clear() {
        WidgetDataStorage.shared.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
