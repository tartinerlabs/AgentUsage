//
//  TokenUsageRepository.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import AgentUsageKit
import SwiftData

/// Background actor for querying token usage data (non-blocking aggregations)
@ModelActor
actor TokenUsageQuerier {
    /// Fetch aggregated summary for a period
    func fetchSummary(for period: UsagePeriod) throws -> TokenUsageSummary {
        let startDate = period.startDate
        let descriptor = FetchDescriptor<TokenLogEntry>(
            predicate: #Predicate { $0.timestamp >= startDate }
        )

        let entries = try modelContext.fetch(descriptor)

        var totalTokens = TokenCount.zero
        var totalCost = 0.0

        for entry in entries {
            totalTokens = totalTokens + entry.tokenCount
            totalCost += entry.costUSD
        }

        return TokenUsageSummary(
            tokens: totalTokens,
            costUSD: totalCost,
            period: period
        )
    }

    /// Fetch usage breakdown by model for a period
    func fetchByModel(for period: UsagePeriod) throws -> [String: TokenCount] {
        let startDate = period.startDate
        let descriptor = FetchDescriptor<TokenLogEntry>(
            predicate: #Predicate { $0.timestamp >= startDate }
        )

        let entries = try modelContext.fetch(descriptor)

        var byModel: [String: TokenCount] = [:]
        for entry in entries {
            let existing = byModel[entry.modelName] ?? .zero
            byModel[entry.modelName] = existing + entry.tokenCount
        }

        return byModel
    }

    /// Fetch per-day token/cost points for the last `days` days (oldest → newest).
    func fetchDailyTokenPoints(days: Int = 30) throws -> [DailyTokenPoint] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let descriptor = FetchDescriptor<TokenLogEntry>(
            predicate: #Predicate { $0.timestamp >= startDate }
        )
        let entries = try modelContext.fetch(descriptor)

        var costByDay: [Date: Double] = [:]
        var tokensByDay: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            costByDay[day, default: 0] += entry.costUSD
            tokensByDay[day, default: 0] += entry.tokenCount.totalTokens
        }

        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            return DailyTokenPoint(date: day, costUSD: costByDay[day] ?? 0, tokens: tokensByDay[day] ?? 0)
        }
    }

    /// Fetch complete snapshot for display
    func fetchSnapshot() throws -> TokenUsageSnapshot {
        let today = try fetchSummary(for: .today)
        let last30Days = try fetchSummary(for: .last30Days)
        let byModel = try fetchByModel(for: .last30Days)

        return TokenUsageSnapshot(
            today: today,
            last30Days: last30Days,
            byModel: byModel,
            fetchedAt: Date()
        )
    }
}

/// Background actor for importing token usage data
@ModelActor
actor TokenUsageImporter {
    /// Import usage entries idempotently, skipping duplicate composite IDs in one batch.
    func importEntries(_ entries: [(entry: UsageEntry, messageId: String, requestId: String)]) throws -> Int {
        guard !entries.isEmpty else { return 0 }

        let candidates = entries.map { item in
            (
                entry: item.entry,
                messageId: item.messageId,
                requestId: item.requestId,
                id: "\(item.messageId):\(item.requestId)"
            )
        }
        var existingIDs = try existingEntryIDs(matching: candidates.map(\.id))
        var insertedCount = 0

        for candidate in candidates where existingIDs.insert(candidate.id).inserted {
            let entry = candidate.entry
            let cost = calculateCost(tokens: entry.tokens, model: entry.model, fastMode: entry.fastMode)

            let logEntry = TokenLogEntry(
                messageId: candidate.messageId,
                requestId: candidate.requestId,
                modelName: entry.model,
                inputTokens: entry.tokens.inputTokens,
                outputTokens: entry.tokens.outputTokens,
                cacheCreationTokens: entry.tokens.cacheCreationTokens,
                cacheReadTokens: entry.tokens.cacheReadTokens,
                timestamp: entry.timestamp,
                costUSD: cost,
                cacheCreation1hTokens: entry.tokens.cacheCreation1hTokens,
                isFastMode: entry.fastMode
            )

            modelContext.insert(logEntry)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        return insertedCount
    }

    private func existingEntryIDs(matching ids: [String]) throws -> Set<String> {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return [] }

        var result = Set<String>()
        for startIndex in stride(from: 0, to: uniqueIDs.count, by: 500) {
            let endIndex = min(startIndex + 500, uniqueIDs.count)
            let batch = Array(uniqueIDs[startIndex..<endIndex])
            let descriptor = FetchDescriptor<TokenLogEntry>(
                predicate: #Predicate { batch.contains($0.id) }
            )
            result.formUnion(try modelContext.fetch(descriptor).map(\.id))
        }
        return result
    }

    /// Cost for a Claude log entry. Routes through the shared `ModelPricing.costUSD` so the persisted
    /// number matches the in-memory aggregation path (tiered cache + fast-mode aware).
    private func calculateCost(tokens: TokenCount, model: String, fastMode: Bool) -> Double {
        ModelPricing.costUSD(
            provider: "anthropic",
            model: model,
            inputTokens: tokens.inputTokens,
            outputTokens: tokens.outputTokens,
            cacheReadTokens: tokens.cacheReadTokens,
            cacheWriteTokens: tokens.cacheCreationTokens,
            reasoningTokens: tokens.reasoningTokens,
            cacheWrite1hTokens: tokens.cacheCreation1hTokens,
            fastMode: fastMode
        ) ?? 0
    }

    /// Recalculate costs for entries that were imported with $0 cost due to unrecognized models
    func recalculateZeroCostEntries() throws -> Int {
        let descriptor = FetchDescriptor<TokenLogEntry>(
            predicate: #Predicate { $0.costUSD == 0 }
        )

        let entries = try modelContext.fetch(descriptor)
        var updatedCount = 0

        for entry in entries {
            let cost = calculateCost(
                tokens: entry.tokenCount,
                model: entry.modelName,
                fastMode: entry.isFastMode
            )
            if cost > 0 {
                entry.costUSD = cost
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            try modelContext.save()
        }

        return updatedCount
    }

    /// Re-price every persisted entry with the current cost model. Used once after a cost-model
    /// upgrade. Rows imported before the 1h-cache / fast-mode fields existed re-price with those
    /// defaulting to 0 / standard, so they gain any model-rate corrections but not the new granularity.
    func recalculateAllCosts() throws -> Int {
        let entries = try modelContext.fetch(FetchDescriptor<TokenLogEntry>())
        var updatedCount = 0

        for entry in entries {
            let cost = calculateCost(
                tokens: entry.tokenCount,
                model: entry.modelName,
                fastMode: entry.isFastMode
            )
            if abs(cost - entry.costUSD) > 1e-9 {
                entry.costUSD = cost
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            try modelContext.save()
        }

        return updatedCount
    }

    /// Batch-delete entries (and stale file bookmarks) older than the 13-month
    /// retention window. Runs in-store without materializing rows — unlike the
    /// legacy fetch-then-loop that used to live on the main-actor facade.
    func cleanupOldEntries() throws {
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? Date()
        try modelContext.delete(
            model: TokenLogEntry.self,
            where: #Predicate { $0.timestamp < cutoffDate }
        )
        // Files untouched for the whole retention window are past the scan cutoff and
        // will never be read again, so their incremental-read bookmarks can go too.
        try modelContext.delete(
            model: ImportedFile.self,
            where: #Predicate { $0.lastModified < cutoffDate }
        )
        try modelContext.save()
    }
}

/// Repository for querying token usage data via SwiftData (main actor for UI)
@MainActor
final class TokenUsageRepository {
    private let modelContext: ModelContext
    private let importer: TokenUsageImporter
    private let querier: TokenUsageQuerier

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.importer = TokenUsageImporter(modelContainer: modelContext.container)
        self.querier = TokenUsageQuerier(modelContainer: modelContext.container)
    }

    // MARK: - Import Operations

    /// Import usage entries in background and update file state
    func importEntries(
        _ entries: [(entry: UsageEntry, messageId: String, requestId: String)],
        forFile fileURL: URL,
        newByteOffset: Int64,
        newFileSize: Int64,
        newModified: Date
    ) async throws {
        await LiteLLMPricingCache.shared.refreshIfNeeded()
        _ = try await importer.importEntries(entries)

        // Update file state on main actor
        try updateFileState(
            path: fileURL.path,
            byteOffset: newByteOffset,
            fileSize: newFileSize,
            lastModified: newModified
        )
    }

    /// Recalculate costs for entries that were imported with $0 cost (e.g., new model pricing added)
    func recalculateZeroCostEntries() async throws -> Int {
        await LiteLLMPricingCache.shared.refreshIfNeeded()
        return try await importer.recalculateZeroCostEntries()
    }

    /// Re-price all persisted entries with the current cost model (used once after a cost-model upgrade).
    func recalculateAllCosts() async throws -> Int {
        await LiteLLMPricingCache.shared.refreshIfNeeded()
        return try await importer.recalculateAllCosts()
    }

    // MARK: - File State Operations

    /// Get all file states as a dictionary for incremental reading
    func getAllFileStates() throws -> [String: TokenUsageService.FileState] {
        let descriptor = FetchDescriptor<ImportedFile>()
        let files = try modelContext.fetch(descriptor)

        var states: [String: TokenUsageService.FileState] = [:]
        for file in files {
            states[file.path] = TokenUsageService.FileState(
                byteOffset: file.lastProcessedByteOffset,
                fileSize: file.fileSize,
                lastModified: file.lastModified
            )
        }
        return states
    }

    /// Get or create ImportedFile record for a file
    func getFileState(for path: String) throws -> ImportedFile? {
        let descriptor = FetchDescriptor<ImportedFile>(
            predicate: #Predicate { $0.path == path }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Update file state after successful import
    func updateFileState(path: String, byteOffset: Int64, fileSize: Int64, lastModified: Date) throws {
        if let existing = try getFileState(for: path) {
            existing.lastProcessedByteOffset = byteOffset
            existing.fileSize = fileSize
            existing.lastModified = lastModified
        } else {
            let newState = ImportedFile(
                path: path,
                lastProcessedByteOffset: byteOffset,
                fileSize: fileSize,
                lastModified: lastModified
            )
            modelContext.insert(newState)
        }

        try modelContext.save()
    }

    /// Reset file state (e.g., when file was truncated)
    func resetFileState(for path: String) throws {
        if let existing = try getFileState(for: path) {
            existing.lastProcessedByteOffset = 0
            existing.fileSize = 0
            try modelContext.save()
        }
    }

    // MARK: - Query Operations (async, runs on background actor)

    /// Fetch aggregated summary for a period (non-blocking)
    func fetchSummary(for period: UsagePeriod) async throws -> TokenUsageSummary {
        try await querier.fetchSummary(for: period)
    }

    /// Fetch usage breakdown by model for a period (non-blocking)
    func fetchByModel(for period: UsagePeriod) async throws -> [String: TokenCount] {
        try await querier.fetchByModel(for: period)
    }

    /// Fetch complete snapshot for display (non-blocking)
    func fetchSnapshot() async throws -> TokenUsageSnapshot {
        try await querier.fetchSnapshot()
    }

    /// Fetch per-day token/cost points (non-blocking)
    func fetchDailyTokenPoints(days: Int = 30) async throws -> [DailyTokenPoint] {
        try await querier.fetchDailyTokenPoints(days: days)
    }

    /// Get total entry count (for debugging/stats)
    func getEntryCount() throws -> Int {
        let descriptor = FetchDescriptor<TokenLogEntry>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Clean up entries older than the retention period (13 months) on the background actor.
    /// 13 months ensures a full calendar year is available for the "Wrapped" feature.
    func cleanupOldEntries() async throws {
        try await importer.cleanupOldEntries()
    }
}
#endif
