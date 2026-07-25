//
//  UsageHistoryRepository.swift
//  AgentUsage
//

import Foundation
import SwiftData
import AgentUsageKit

@ModelActor
actor UsageHistoryRepository {
    static let maxDays = 30
    private static let legacyStorageKey = "usageHistory"
    private static let migrationKey = "didMigrateUsageHistoryToSwiftData"
    /// Bumped to V3: V2 ran once and then `record(snapshot:)` kept writing Claude
    /// history to the legacy table only, so anything recorded after V2 never
    /// reached the provider-neutral table the trends chart reads. Re-running the
    /// copy is safe because peaks merge with `max`.
    private static let genericMigrationKey = "didMigrateProviderWindowHistoryV3"

    private var hasMigrated = false
    /// Day the retention scan last ran, so it runs once per day rather than per refresh.
    private var lastCleanupDay: Date?

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

    /// Record Claude's snapshot through the provider-neutral path so its history
    /// lands in the same table as every other provider.
    func record(snapshot: UsageSnapshot) throws {
        try record(providerSnapshot: ProviderUsageSnapshot(claude: snapshot))
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
        // Recording runs on every refresh; rows can only age out when the day
        // rolls over, so the delete scan does not need to run each time.
        let today = Calendar.current.startOfDay(for: providerSnapshot.fetchedAt)
        if lastCleanupDay != today {
            try cleanupOldRecords()
            lastCleanupDay = today
        }
        try modelContext.save()
    }

    /// Daily peaks for every provider over the last `days` days.
    func fetchProviderPeaks(days: Int = maxDays) throws -> ProviderUsageHistory {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ProviderWindowDailyPeakEntity>(
            predicate: #Predicate { $0.date >= cutoffDate },
            sortBy: [SortDescriptor(\ProviderWindowDailyPeakEntity.date)]
        )
        let peaks = try modelContext.fetch(descriptor).compactMap { entity -> ProviderWindowPeak? in
            // Rows written by a build that knew a provider this one doesn't.
            guard let provider = Provider(rawValue: entity.providerID) else { return nil }
            return ProviderWindowPeak(
                provider: provider,
                windowID: UsageWindowID(rawValue: entity.windowID),
                windowLabel: entity.windowLabel,
                date: entity.date,
                peakUtilization: entity.peakUtilization
            )
        }
        return ProviderUsageHistory(peaks: peaks)
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
