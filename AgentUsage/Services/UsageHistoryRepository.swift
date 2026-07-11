//
//  UsageHistoryRepository.swift
//  AgentUsage
//

import Foundation
import SwiftData
import AgentUsageKit

@ModelActor
actor UsageHistoryRepository {
    private static let maxDays = 30
    private static let legacyStorageKey = "usageHistory"
    private static let migrationKey = "didMigrateUsageHistoryToSwiftData"
    private static let genericMigrationKey = "didMigrateProviderWindowHistoryV2"

    private var hasMigrated = false

    func migrateFromUserDefaultsIfNeeded(defaults: UserDefaults = .standard) throws {
        guard !hasMigrated else { return }
        hasMigrated = true

        if !defaults.bool(forKey: Self.migrationKey) {
            if let data = defaults.data(forKey: Self.legacyStorageKey),
               let history = try? JSONDecoder().decode(UsageHistory.self, from: data) {
                for record in history.records {
                    try upsert(record)
                }
            }
            defaults.set(true, forKey: Self.migrationKey)
        }
        try migrateLegacyEntitiesIfNeeded(defaults: defaults)
        try cleanupOldRecords()
        try modelContext.save()
    }

    func migrateLegacyEntitiesIfNeeded(defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: Self.genericMigrationKey) else { return }
        let legacy = try modelContext.fetch(FetchDescriptor<DailyUsageRecordEntity>())
        for record in legacy {
            let windows = [
                UsageWindow(
                    utilization: record.peakSessionUtilization,
                    resetsAt: record.date,
                    windowType: .session
                ),
                UsageWindow(
                    utilization: record.peakOpusUtilization,
                    resetsAt: record.date,
                    windowType: .opus
                ),
                record.peakSonnetUtilization.map {
                    UsageWindow(utilization: $0, resetsAt: record.date, windowType: .sonnet)
                },
                record.peakFableUtilization.map {
                    UsageWindow(utilization: $0, resetsAt: record.date, windowType: .fable)
                },
            ] as [UsageWindow?]
            for window in windows {
                guard let window else { continue }
                try upsert(provider: .claude, window: window, date: record.date, updatedAt: record.updatedAt)
            }
        }
        defaults.set(true, forKey: Self.genericMigrationKey)
        try modelContext.save()
    }

    func record(snapshot: UsageSnapshot) throws {
        let id = DailyUsageRecordEntity.id(for: Date())
        if let existing = try existingEntity(id: id) {
            existing.update(with: existing.record.mergedWith(snapshot: snapshot))
        } else {
            modelContext.insert(DailyUsageRecordEntity(record: .from(snapshot: snapshot)))
            // Records can only age past the cutoff when a new day starts
            try cleanupOldRecords()
        }
        try modelContext.save()
    }

    func record(providerSnapshot: ProviderUsageSnapshot) throws {
        for window in providerSnapshot.windows where !window.isExpired(from: providerSnapshot.fetchedAt) {
            try upsert(
                provider: providerSnapshot.provider,
                window: window,
                date: providerSnapshot.fetchedAt,
                updatedAt: providerSnapshot.fetchedAt
            )
        }
        try cleanupOldRecords()
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
        try modelContext.delete(model: ProviderWindowDailyPeakEntity.self)
        try modelContext.save()
    }

    private func upsert(_ record: DailyUsageRecord) throws {
        let id = DailyUsageRecordEntity.id(for: record.date)
        if let existing = try existingEntity(id: id) {
            existing.update(with: record)
        } else {
            modelContext.insert(DailyUsageRecordEntity(record: record))
        }
    }

    private func existingEntity(id: String) throws -> DailyUsageRecordEntity? {
        var descriptor = FetchDescriptor<DailyUsageRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func upsert(
        provider: Provider,
        window: UsageWindow,
        date: Date,
        updatedAt: Date
    ) throws {
        let id = ProviderWindowDailyPeakEntity.id(
            provider: provider,
            windowID: window.windowID,
            date: date
        )
        var descriptor = FetchDescriptor<ProviderWindowDailyPeakEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.merge(window: window, updatedAt: updatedAt)
        } else {
            modelContext.insert(ProviderWindowDailyPeakEntity(
                provider: provider,
                window: window,
                date: date,
                updatedAt: updatedAt
            ))
        }
    }

    private func cleanupOldRecords() throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.maxDays, to: Date()) ?? Date()
        try modelContext.delete(
            model: DailyUsageRecordEntity.self,
            where: #Predicate { $0.date < cutoffDate }
        )
        try modelContext.delete(
            model: ProviderWindowDailyPeakEntity.self,
            where: #Predicate { $0.date < cutoffDate }
        )
    }
}
