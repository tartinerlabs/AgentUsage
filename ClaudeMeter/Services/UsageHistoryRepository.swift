//
//  UsageHistoryRepository.swift
//  ClaudeMeter
//

import Foundation
import SwiftData
import ClaudeMeterKit

@ModelActor
actor UsageHistoryRepository {
    private static let maxDays = 30
    private static let legacyStorageKey = "usageHistory"
    private static let migrationKey = "didMigrateUsageHistoryToSwiftData"

    func migrateFromUserDefaultsIfNeeded(defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        defer { defaults.set(true, forKey: Self.migrationKey) }

        guard let data = defaults.data(forKey: Self.legacyStorageKey),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data) else {
            return
        }

        for record in history.records {
            try upsert(record)
        }
        try cleanupOldRecords()
    }

    func record(snapshot: UsageSnapshot) throws {
        let today = Calendar.current.startOfDay(for: Date())
        let id = DailyUsageRecordEntity.id(for: today)
        var descriptor = FetchDescriptor<DailyUsageRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        let updatedRecord: DailyUsageRecord
        if let existing = try modelContext.fetch(descriptor).first {
            updatedRecord = existing.record.mergedWith(snapshot: snapshot)
            existing.update(with: updatedRecord)
        } else {
            updatedRecord = DailyUsageRecord.from(snapshot: snapshot)
            modelContext.insert(DailyUsageRecordEntity(record: updatedRecord))
        }

        try cleanupOldRecords(save: false)
        try modelContext.save()
    }

    func fetchHistory() throws -> UsageHistory {
        let records = try fetchRecords(days: Self.maxDays)
        return UsageHistory(records: records, maxDays: Self.maxDays)
    }

    func fetchRecords(days: Int) throws -> [DailyUsageRecord] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<DailyUsageRecordEntity>(
            predicate: #Predicate { $0.date >= cutoffDate },
            sortBy: [SortDescriptor(\DailyUsageRecordEntity.date)]
        )
        return try modelContext.fetch(descriptor).map(\.record)
    }

    func clear() throws {
        try modelContext.delete(model: DailyUsageRecordEntity.self)
        try modelContext.save()
    }

    private func upsert(_ record: DailyUsageRecord) throws {
        let normalized = DailyUsageRecord(
            date: Calendar.current.startOfDay(for: record.date),
            peakSessionUtilization: record.peakSessionUtilization,
            peakOpusUtilization: record.peakOpusUtilization,
            peakSonnetUtilization: record.peakSonnetUtilization,
            peakFableUtilization: record.peakFableUtilization,
            updatedAt: record.updatedAt
        )
        let id = DailyUsageRecordEntity.id(for: normalized.date)
        var descriptor = FetchDescriptor<DailyUsageRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(with: normalized)
        } else {
            modelContext.insert(DailyUsageRecordEntity(record: normalized))
        }
        try modelContext.save()
    }

    private func cleanupOldRecords(save: Bool = true) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.maxDays, to: Date()) ?? Date()
        try modelContext.delete(
            model: DailyUsageRecordEntity.self,
            where: #Predicate { $0.date < cutoffDate }
        )
        if save {
            try modelContext.save()
        }
    }
}
