//
//  WidgetDataManager.swift
//  ClaudeMeter
//

#if os(iOS)
import Foundation
import ClaudeMeterKit
import WidgetKit

/// Manages shared data between the main app and widget extension via App Groups
actor WidgetDataManager {
    static let shared = WidgetDataManager()
    private let suiteName = "group.com.tartinerlabs.ClaudeMeter"
    private let snapshotKey = "cachedUsageSnapshot"

    private init() {}

    /// Save snapshot to shared UserDefaults and reload widget timelines
    func save(_ snapshot: UsageSnapshot) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("[WidgetDataManager] Failed to access App Groups UserDefaults")
            return
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: snapshotKey)
            print("[WidgetDataManager] Saved snapshot to App Groups")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[WidgetDataManager] Failed to encode snapshot: \(error)")
        }
    }

    /// Load snapshot from shared UserDefaults (can be called from widget extension)
    nonisolated func load() -> UsageSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// Clear cached data
    func clear() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
