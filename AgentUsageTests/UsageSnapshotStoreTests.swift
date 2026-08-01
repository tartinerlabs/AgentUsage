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

    @Test func roundTripsProviderEffortSummaries() throws {
        let testDefaults = TestUserDefaults()
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let summary = EffortPeriodSummary(
            period: .last7Days,
            levels: [
                EffortLevelCount(level: .high, sessionCount: 3),
                EffortLevelCount(level: .xhigh, sessionCount: 2),
            ],
            classifiedSessionCount: 5,
            unclassifiedSessionCount: 1
        )
        let providerSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [],
            effortSummaries: [summary],
            fetchedAt: fetchedAt
        )

        store.save(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [providerSnapshot],
            fetchedAt: fetchedAt
        )
        let cached = try #require(store.load())
        let cachedProvider = try #require(cached.providerSnapshots.first)

        #expect(cachedProvider.effortSummaries == [summary])
        #expect(cachedProvider.effortSummary(for: .last7Days) == summary)
        #expect(cachedProvider.effortSummary(for: .last7Days)?.totalSessionCount == 6)
    }

    @Test func roundTripsCursorDynamicWindowsAndExtraUsage() throws {
        let testDefaults = TestUserDefaults()
        let store = UsageSnapshotStore(defaults: testDefaults.defaults)
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let providerSnapshot = ProviderUsageSnapshot(
            provider: .cursor,
            windows: [
                UsageWindow(
                    utilization: 54,
                    resetsAt: fetchedAt.addingTimeInterval(31 * 24 * 3_600),
                    windowID: "cursor.total",
                    displayName: "Total usage",
                    totalDuration: 31 * 24 * 3_600
                ),
            ],
            extraUsage: ExtraUsageCost(used: 8, limit: 50, currencyCode: "USD"),
            planName: "Pro",
            fetchedAt: fetchedAt
        )

        store.save(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [providerSnapshot],
            fetchedAt: fetchedAt
        )
        let cached = try #require(store.load()?.providerSnapshots.first)

        #expect(cached.provider == .cursor)
        #expect(cached.windows.first?.windowID.rawValue == "cursor.total")
        #expect(cached.windows.first?.windowType == .custom)
        #expect(cached.extraUsage?.used == 8)
        #expect(cached.extraUsage?.limit == 50)
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
