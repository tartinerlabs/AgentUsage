//
//  WidgetDataStorage.swift
//  ClaudeMeterKit
//
//  Shared widget data storage for cross-process communication via App Groups
//  This is a read-only interface used by both the main app and widget extension
//

import Foundation

/// Shared widget data storage for reading cached snapshots
/// Used by both the main iOS app and widget extension via App Groups
public final class WidgetDataStorage: Sendable {
    /// Shared instance for accessing widget data
    public static let shared = WidgetDataStorage()

    /// App Group suite name for shared UserDefaults
    public static let suiteName = "group.com.tartinerlabs.ClaudeMeter"

    /// Key for cached usage snapshot
    public static let snapshotKey = "cachedUsageSnapshot"

    private init() {}

    /// Load snapshot from shared UserDefaults
    /// - Returns: Cached usage snapshot, or nil if not available
    public func load() -> UsageSnapshot? {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// Save snapshot to shared UserDefaults
    /// Note: This does not trigger widget timeline refresh - caller should handle that
    /// - Parameter snapshot: Usage snapshot to cache
    /// - Returns: True if save succeeded
    @discardableResult
    public func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else {
            return false
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.snapshotKey)
            return true
        } catch {
            return false
        }
    }

    /// Clear cached data
    public func clear() {
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else { return }
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
