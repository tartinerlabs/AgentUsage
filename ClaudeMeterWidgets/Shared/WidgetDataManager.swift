//
//  WidgetDataManager.swift
//  ClaudeMeterWidgets
//
//  Shared data manager for widget extension
//  Note: This is a simplified version for reading cached data in the widget
//

import Foundation
import ClaudeMeterKit

/// Manages shared data between the main app and widget extension via App Groups
enum WidgetDataManager {
    static let shared = WidgetDataManagerImpl()
}

final class WidgetDataManagerImpl: Sendable {
    private let suiteName = "group.com.tartinerlabs.ClaudeMeter"
    private let snapshotKey = "cachedUsageSnapshot"

    /// Load snapshot from shared UserDefaults
    func load() -> UsageSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
