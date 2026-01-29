//
//  WidgetDataManager.swift
//  ClaudeMeter
//
//  iOS app's widget data manager with WidgetKit integration
//  Uses ClaudeMeterKit's WidgetDataStorage for data persistence
//

#if os(iOS)
import Foundation
import ClaudeMeterKit
import OSLog
import WidgetKit

/// Manages shared data between the main app and widget extension via App Groups
/// Adds WidgetKit-specific functionality (timeline refresh) on top of shared storage
actor WidgetDataManager: WidgetDataServiceProtocol {
    static let shared = WidgetDataManager()

    private init() {}

    /// Save snapshot to shared storage and reload widget timelines
    func save(_ snapshot: UsageSnapshot) {
        if WidgetDataStorage.shared.save(snapshot) {
            Logger.widget.debug("Saved snapshot to App Groups")
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            Logger.widget.error("Failed to save snapshot")
        }
    }

    /// Load snapshot from shared storage
    nonisolated func load() -> UsageSnapshot? {
        WidgetDataStorage.shared.load()
    }

    /// Clear cached data and reload widget timelines
    func clear() {
        WidgetDataStorage.shared.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
