//
//  WidgetDataManager.swift
//  AgentUsageWidgets
//
//  Wrapper around AgentUsageKit's WidgetDataStorage for widget extension
//

import Foundation
import AgentUsageKit

/// Manages shared data between the main app and widget extension via App Groups
/// Uses AgentUsageKit's WidgetDataStorage for consistent data access
enum WidgetDataManager {
    /// Load snapshot from shared storage
    static func load() -> UsageSnapshot? {
        WidgetDataStorage.shared.load()
    }
}
