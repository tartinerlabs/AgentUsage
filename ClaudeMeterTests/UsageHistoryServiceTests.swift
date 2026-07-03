//
//  UsageHistoryServiceTests.swift
//  ClaudeMeterTests
//

import Foundation
import SwiftData
import Testing
@testable import ClaudeMeter
@testable import ClaudeMeterKit

@Suite("UsageHistoryService", .serialized)
struct UsageHistoryServiceTests {
    @Test func recordsSnapshotsToSwiftDataAndKeepsDailyPeaks() async throws {
        let suiteName = "UsageHistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = try makeService(defaults: defaults)

        await service.record(snapshot: snapshot(session: 20, opus: 30, sonnet: 10, fable: 5))
        await service.record(snapshot: snapshot(session: 35, opus: 25, sonnet: 15, fable: 8))

        let records = await service.getRecords(days: 30)
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.peakSessionUtilization == 35)
        #expect(record.peakOpusUtilization == 30)
        #expect(record.peakSonnetUtilization == 15)
        #expect(record.peakFableUtilization == 8)
    }

    @Test func migratesLegacyUserDefaultsHistoryToSwiftData() async throws {
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
        let records = await service.getRecords(days: 30)

        let migrated = try #require(records.first)
        #expect(records.count == 1)
        #expect(migrated.peakSessionUtilization == 44)
        #expect(migrated.peakOpusUtilization == 55)
        #expect(migrated.peakSonnetUtilization == 66)
        #expect(migrated.peakFableUtilization == 77)
        #expect(defaults.bool(forKey: "didMigrateUsageHistoryToSwiftData"))
        #expect(defaults.data(forKey: "usageHistory") != nil)
    }

    private func makeService(defaults: UserDefaults = .standard) throws -> UsageHistoryService {
        let schema = Schema([DailyUsageRecordEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let repository = UsageHistoryRepository(modelContainer: container)
        return UsageHistoryService(repository: repository, defaults: defaults)
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
