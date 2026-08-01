//
//  WidgetDataServiceProtocol.swift
//  AgentUsage
//

#if os(iOS)
import Foundation
import AgentUsageKit

/// Protocol for managing widget data via App Groups
/// Enables dependency injection and testing with mock implementations
protocol WidgetDataServiceProtocol: Actor {
    /// Save all enabled provider snapshots and reload widget timelines.
    func save(_ snapshots: [ProviderUsageSnapshot]) async

    /// Load cached provider snapshots from shared UserDefaults.
    nonisolated func load() -> [ProviderUsageSnapshot]

    /// Clear cached data and reload widget timelines
    func clear() async
}
#endif
