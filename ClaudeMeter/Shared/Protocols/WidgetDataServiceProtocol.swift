//
//  WidgetDataServiceProtocol.swift
//  ClaudeMeter
//

#if os(iOS)
import Foundation
import ClaudeMeterKit

/// Protocol for managing widget data via App Groups
/// Enables dependency injection and testing with mock implementations
protocol WidgetDataServiceProtocol: Actor {
    /// Save snapshot to shared UserDefaults and reload widget timelines
    /// - Parameter snapshot: Usage snapshot to cache for widgets
    func save(_ snapshot: UsageSnapshot) async

    /// Load snapshot from shared UserDefaults
    /// - Returns: Cached usage snapshot, or nil if not available
    nonisolated func load() -> UsageSnapshot?

    /// Clear cached data and reload widget timelines
    func clear() async
}
#endif
