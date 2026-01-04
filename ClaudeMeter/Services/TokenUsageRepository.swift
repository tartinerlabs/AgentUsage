//
//  TokenUsageRepository.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
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
    /// Import usage entries, skipping duplicates via unique constraint
    func importEntries(_ entries: [(entry: UsageEntry, messageId: String, requestId: String)]) throws -> Int {
        guard !entries.isEmpty else { return 0 }

        var insertedCount = 0
        for (entry, messageId, requestId) in entries {
            let compositeId = "\(messageId):\(requestId)"

            // Check if already exists
            var descriptor = FetchDescriptor<TokenLogEntry>(
                predicate: #Predicate { $0.id == compositeId }
            )
            descriptor.fetchLimit = 1
            let existing = try modelContext.fetchCount(descriptor)
            guard existing == 0 else { continue }

            // Calculate cost at import time
            let cost = calculateCost(tokens: entry.tokens, model: entry.model)

            let logEntry = TokenLogEntry(
                messageId: messageId,
                requestId: requestId,
                modelName: entry.model,
                inputTokens: entry.tokens.inputTokens,
                outputTokens: entry.tokens.outputTokens,
                cacheCreationTokens: entry.tokens.cacheCreationTokens,
                cacheReadTokens: entry.tokens.cacheReadTokens,
                timestamp: entry.timestamp,
                costUSD: cost
            )

            modelContext.insert(logEntry)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        return insertedCount
    }

    private func calculateCost(tokens: TokenCount, model: String) -> Double {
        guard let rates = ModelPricing.rates(for: model) else { return 0 }
        let inputCost = Double(tokens.inputTokens) * rates.inputPerMTok / 1_000_000
        let outputCost = Double(tokens.outputTokens) * rates.outputPerMTok / 1_000_000
        let cacheWriteCost = Double(tokens.cacheCreationTokens) * rates.cacheWritePerMTok / 1_000_000
        let cacheReadCost = Double(tokens.cacheReadTokens) * rates.cacheReadPerMTok / 1_000_000
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
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
        _ = try await importer.importEntries(entries)

        // Update file state on main actor
        try updateFileState(
            path: fileURL.path,
            byteOffset: newByteOffset,
            fileSize: newFileSize,
            lastModified: newModified
        )
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

    /// Get total entry count (for debugging/stats)
    func getEntryCount() throws -> Int {
        let descriptor = FetchDescriptor<TokenLogEntry>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Clean up entries older than retention period (13 months)
    /// 13 months ensures full calendar year available for "Wrapped" feature
    func cleanupOldEntries() throws {
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<TokenLogEntry>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )

        let oldEntries = try modelContext.fetch(descriptor)
        for entry in oldEntries {
            modelContext.delete(entry)
        }

        try modelContext.save()
    }
}
#endif
