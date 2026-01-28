//
//  WidgetDataManager.swift
//  ClaudeMeterWidgets
//
//  Wrapper around ClaudeMeterKit's WidgetDataStorage for widget extension
//

import Foundation
import ClaudeMeterKit

/// Manages shared data between the main app and widget extension via App Groups
/// Uses ClaudeMeterKit's WidgetDataStorage for consistent data access
enum WidgetDataManager {
    /// Load snapshot from shared storage
    static func load() -> UsageSnapshot? {
        WidgetDataStorage.shared.load()
    }
}
