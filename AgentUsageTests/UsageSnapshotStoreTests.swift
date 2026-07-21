//
//  UsageSnapshotStoreTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("UsageSnapshotStore")
struct UsageSnapshotStoreTests {
    @Test func roundTripsSnapshotPlanAndFetchTime() throws {
        let testDefaults = TestUserDefaults()
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = makeSnapshot(fetchedAt: fetchedAt)

        store.save(snapshot: snapshot, planType: "Max 20x", fetchedAt: fetchedAt)
        let cached = try #require(store.load())
        let cachedSnapshot = try #require(cached.snapshot)

        #expect(cachedSnapshot.session.utilization == 42)
        #expect(cachedSnapshot.opus.utilization == 18)
        #expect(cached.planType == "Max 20x")
        #expect(cached.lastSuccessfulFetchTime == fetchedAt)
        #expect(store.lastSuccessfulFetchTime == fetchedAt)
    }

    @Test func roundTripsProviderSnapshotsWithoutClaudeSnapshot() throws {
        let testDefaults = TestUserDefaults()
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let providerSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 54,
                    resetsAt: fetchedAt.addingTimeInterval(3_600),
                    windowType: .codexFiveHour
                ),
            ],
            planName: "Plus",
            fetchedAt: fetchedAt
        )

        store.save(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [providerSnapshot],
            fetchedAt: fetchedAt
        )
        let cached = try #require(store.load())

        #expect(cached.snapshot == nil)
        #expect(cached.providerSnapshots.map(\.provider) == [.codex])
        #expect(cached.providerSnapshots.first?.planName == "Plus")
        #expect(cached.lastSuccessfulFetchTime == fetchedAt)
    }

    @Test func invalidSnapshotDataIsIgnored() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(Data("not-json".utf8), forKey: UsageSnapshotStore.snapshotKey)
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)

        #expect(store.load() == nil)
    }

    @Test func missingPlanAndFetchTimeUseExistingDefaults() throws {
        let testDefaults = TestUserDefaults()
        let snapshot = makeSnapshot(fetchedAt: Date())
        testDefaults.defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: UsageSnapshotStore.snapshotKey
        )
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)

        let cached = try #require(store.load())

        #expect(cached.planType == "Free")
        #expect(cached.lastSuccessfulFetchTime == nil)
    }

    private func makeSnapshot(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: 42,
                resetsAt: fetchedAt.addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 18,
                resetsAt: fetchedAt.addingTimeInterval(7_200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: fetchedAt
        )
    }
}
