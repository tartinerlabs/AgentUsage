//
//  UsageSnapshotStore.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit

struct CachedUsageSnapshot {
    let snapshot: UsageSnapshot?
    let planType: String
    let providerSnapshots: [ProviderUsageSnapshot]
    let lastSuccessfulFetchTime: Date?
}

/// Persists the last successful Claude usage response without owning UI state.
struct UsageSnapshotStore {
    static let snapshotKey = "cachedUsageSnapshot"
    static let planKey = "cachedPlanType"
    static let providerSnapshotsKey = "cachedProviderUsageSnapshots"
    static let fetchTimeKey = "cachedUsageSnapshotTime"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CachedUsageSnapshot? {
        let snapshot = defaults.data(forKey: Self.snapshotKey).flatMap {
            try? JSONDecoder().decode(UsageSnapshot.self, from: $0)
        }
        let providerSnapshots = defaults.data(forKey: Self.providerSnapshotsKey).flatMap {
            try? JSONDecoder().decode([ProviderUsageSnapshot].self, from: $0)
        } ?? []

        guard snapshot != nil || !providerSnapshots.isEmpty else {
            return nil
        }

        return CachedUsageSnapshot(
            snapshot: snapshot,
            planType: defaults.string(forKey: Self.planKey) ?? "Free",
            providerSnapshots: providerSnapshots,
            lastSuccessfulFetchTime: lastSuccessfulFetchTime
        )
    }

    func save(
        snapshot: UsageSnapshot?,
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot] = [],
        fetchedAt: Date
    ) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        } else {
            defaults.removeObject(forKey: Self.snapshotKey)
        }

        if let data = try? JSONEncoder().encode(providerSnapshots) {
            defaults.set(data, forKey: Self.providerSnapshotsKey)
        }

        defaults.set(planType, forKey: Self.planKey)
        defaults.set(fetchedAt.timeIntervalSince1970, forKey: Self.fetchTimeKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.removeObject(forKey: Self.planKey)
        defaults.removeObject(forKey: Self.providerSnapshotsKey)
        defaults.removeObject(forKey: Self.fetchTimeKey)
    }

    var lastSuccessfulFetchTime: Date? {
        let timestamp = defaults.double(forKey: Self.fetchTimeKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
}
