//
//  UsageHistoryServiceTests.swift
//  AgentUsageTests
//

import Foundation
import SwiftData
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("UsageHistoryService", .serialized)
struct UsageHistoryServiceTests {
    @Test func recordsSnapshotsToSwiftDataAndKeepsDailyPeaks() async throws {
        let suiteName = "UsageHistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = try makeService(defaults: defaults)

        await service.record(snapshot: snapshot(session: 20, opus: 30, sonnet: 10, fable: 5))
        await service.record(snapshot: snapshot(session: 35, opus: 25, sonnet: 15, fable: 8))

        let history = await service.getProviderHistory(days: 30)
        #expect(history.providers == [.claude])
        #expect(peak(in: history, .claude, .session) == 35)
        #expect(peak(in: history, .claude, .opus) == 30)
        #expect(peak(in: history, .claude, .sonnet) == 15)
        #expect(peak(in: history, .claude, .fable) == 8)
        // Same day, so each window collapses to a single peak.
        #expect(history.peaks.count == 4)
    }

    @Test func recordsWindowsForEveryProvider() async throws {
        let suiteName = "UsageHistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = try makeService(defaults: defaults)

        await service.record(snapshot: snapshot(session: 20, opus: 30, sonnet: nil, fable: nil))
        await service.record(providerSnapshot: ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 64,
                    resetsAt: Date().addingTimeInterval(3_600),
                    windowType: .session
                )
            ],
            fetchedAt: Date()
        ))

        let history = await service.getProviderHistory(days: 30)
        #expect(history.providers == [.claude, .codex])
        #expect(peak(in: history, .codex, .session) == 64)
        // One line per provider, each collapsed to its worst window that day.
        let series = history.seriesByProvider()
        #expect(series.count == 2)
        #expect(series.first { $0.provider == .codex }?.points.first?.utilization == 64)
    }

    @Test func migratesLegacyUserDefaultsHistoryToProviderPeaks() async throws {
        let suiteName = "UsageHistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let yesterday = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        let legacyRecord = DailyUsageRecord(
            date: yesterday,
            peakSessionUtilization: 44,
            peakOpusUtilization: 55,
            peakSonnetUtilization: 66,
            peakFableUtilization: 77,
            updatedAt: yesterday
        )
        let legacyHistory = UsageHistory(records: [legacyRecord])
        defaults.set(try JSONEncoder().encode(legacyHistory), forKey: "usageHistory")

        let service = try makeService(defaults: defaults)
        let history = await service.getProviderHistory(days: 30)

        #expect(history.providers == [.claude])
        #expect(peak(in: history, .claude, .session) == 44)
        #expect(peak(in: history, .claude, .opus) == 55)
        #expect(peak(in: history, .claude, .sonnet) == 66)
        #expect(peak(in: history, .claude, .fable) == 77)
        #expect(defaults.bool(forKey: "didMigrateUsageHistoryToSwiftData"))
        #expect(defaults.bool(forKey: "didMigrateProviderWindowHistoryV3"))
        #expect(defaults.data(forKey: "usageHistory") != nil)
    }

    /// V2 shipped the provider-neutral table but kept writing Claude history to
    /// the legacy one, so the V3 pass has to pick those rows up.
    @Test func remigratesLegacyEntitiesRecordedAfterTheV2Migration() async throws {
        let suiteName = "UsageHistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "didMigrateProviderWindowHistoryV2")

        let container = try makeContainer()
        let context = ModelContext(container)
        let yesterday = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        context.insert(DailyUsageRecordEntity(record: DailyUsageRecord(
            date: yesterday,
            peakSessionUtilization: 12,
            peakOpusUtilization: 90,
            peakSonnetUtilization: nil,
            peakFableUtilization: nil,
            updatedAt: yesterday
        )))
        try context.save()

        let service = UsageHistoryService(
            repository: UsageHistoryRepository(modelContainer: container),
            defaults: defaults
        )
        let history = await service.getProviderHistory(days: 30)

        #expect(peak(in: history, .claude, .opus) == 90)
        #expect(history.stats(for: .claude).criticalDays == 1)
    }

    // MARK: - Helpers

    private func peak(
        in history: ProviderUsageHistory,
        _ provider: Provider,
        _ window: UsageWindowType
    ) -> Double? {
        history.peaks(for: provider)
            .first { $0.windowID.rawValue == window.rawValue }?
            .peakUtilization
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            DailyUsageRecordEntity.self,
            ProviderWindowDailyPeakEntity.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeService(defaults: UserDefaults = .standard) throws -> UsageHistoryService {
        UsageHistoryService(
            repository: UsageHistoryRepository(modelContainer: try makeContainer()),
            defaults: defaults
        )
    }

    private func snapshot(session: Double, opus: Double, sonnet: Double?, fable: Double?) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: session,
                resetsAt: Date().addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: opus,
                resetsAt: Date().addingTimeInterval(86_400),
                windowType: .opus
            ),
            sonnet: sonnet.map {
                UsageWindow(
                    utilization: $0,
                    resetsAt: Date().addingTimeInterval(86_400),
                    windowType: .sonnet
                )
            },
            fable: fable.map {
                UsageWindow(
                    utilization: $0,
                    resetsAt: Date().addingTimeInterval(86_400),
                    windowType: .fable
                )
            },
            fetchedAt: Date()
        )
    }
}
