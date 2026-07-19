//
//  UsageSnapshotStore.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit

struct CachedUsageSnapshot {
    let snapshot: UsageSnapshot
    let planType: String
    let lastSuccessfulFetchTime: Date?
}

/// Persists the last successful Claude usage response without owning UI state.
struct UsageSnapshotStore {
    static let snapshotKey = "cachedUsageSnapshot"
    static let planKey = "cachedPlanType"
    static let fetchTimeKey = "cachedUsageSnapshotTime"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CachedUsageSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return nil
        }

        return CachedUsageSnapshot(
            snapshot: snapshot,
            planType: defaults.string(forKey: Self.planKey) ?? "Free",
            lastSuccessfulFetchTime: lastSuccessfulFetchTime
        )
    }

    func save(snapshot: UsageSnapshot, planType: String, fetchedAt: Date) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
        defaults.set(planType, forKey: Self.planKey)
        defaults.set(fetchedAt.timeIntervalSince1970, forKey: Self.fetchTimeKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.removeObject(forKey: Self.planKey)
        defaults.removeObject(forKey: Self.fetchTimeKey)
    }

    var lastSuccessfulFetchTime: Date? {
        let timestamp = defaults.double(forKey: Self.fetchTimeKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
}
