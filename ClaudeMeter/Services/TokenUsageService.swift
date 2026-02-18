//
//  TokenUsageService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog
import CryptoKit

actor TokenUsageService: TokenUsageServiceProtocol {
    private let fileManager = FileManager.default

    // Reentrancy guard: reuse in-flight fetch instead of starting a new one
    private var inFlightTask: Task<TokenUsageSnapshot, Error>?

    // Caching and state tracking
    private var lastSnapshot: TokenUsageSnapshot?
    private var fileState: [URL: Date] = [:]
    private var cachedEntriesByFile: [URL: [UsageEntry]] = [:]

    // Reuse a single formatter
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Fetch token usage from local JSONL logs
    func fetchUsage() async throws -> TokenUsageSnapshot {
        if let task = inFlightTask {
            return try await task.value
        }

        let task = Task<TokenUsageSnapshot, Error> {
            return try await self.computeSnapshot()
        }

        inFlightTask = task
        defer { inFlightTask = nil }
        return try await task.value
    }

    /// Represents file state for incremental reading
    struct FileState {
        let byteOffset: Int64
        let fileSize: Int64
        let lastModified: Date

        static let initial = FileState(byteOffset: 0, fileSize: 0, lastModified: .distantPast)
    }

    /// Result of incremental file parsing
    struct IncrementalParseResult {
        let entries: [(entry: UsageEntry, messageId: String, requestId: String)]
        let newByteOffset: Int64
        let newFileSize: Int64
        let newModified: Date
    }

    /// Fetch parsed entries grouped by file for SwiftData import (incremental)
    /// Returns entries with messageId and requestId for deduplication
    /// Uses 13-month window to ensure full calendar year for "Wrapped" feature
    func fetchParsedEntries(
        fileStates: [String: FileState] = [:]
    ) async throws -> [URL: IncrementalParseResult] {
        let fileCutoff = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? Date()
        let jsonlFiles = try await self.loadAllJSONLFiles(modifiedAfter: fileCutoff)

        var result: [URL: IncrementalParseResult] = [:]

        for file in jsonlFiles {
            let state = fileStates[file.path] ?? .initial
            let parseResult = try parseJSONLFileIncremental(at: file, fromState: state)

            // Only include files that had new entries
            if !parseResult.entries.isEmpty {
                result[file] = parseResult
            } else if parseResult.newByteOffset != state.byteOffset {
                // File was read but no new entries (e.g., non-assistant entries)
                // Still update state to avoid re-reading
                result[file] = parseResult
            }
        }

        return result
    }

    /// Parse JSONL file incrementally from a given byte offset
    private func parseJSONLFileIncremental(
        at url: URL,
        fromState state: FileState
    ) throws -> IncrementalParseResult {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let currentSize = (attributes[.size] as? Int64) ?? 0
        let currentModified = (attributes[.modificationDate] as? Date) ?? Date()

        // Determine import action
        let action: ImportAction
        if currentSize < state.fileSize {
            action = .resetAndImport
        } else if currentSize > state.fileSize || currentModified > state.lastModified {
            action = .incrementalImport
        } else {
            action = .skip
        }

        switch action {
        case .skip:
            return IncrementalParseResult(
                entries: [],
                newByteOffset: state.byteOffset,
                newFileSize: state.fileSize,
                newModified: state.lastModified
            )

        case .resetAndImport:
            // File truncated - read from beginning
            let entries = try parseJSONLFileWithIDs(at: url)
            return IncrementalParseResult(
                entries: entries,
                newByteOffset: currentSize,
                newFileSize: currentSize,
                newModified: currentModified
            )

        case .incrementalImport:
            // Read only new content from byte offset
            let entries = try parseJSONLFileFromOffset(at: url, offset: state.byteOffset)
            return IncrementalParseResult(
                entries: entries,
                newByteOffset: currentSize,
                newFileSize: currentSize,
                newModified: currentModified
            )
        }
    }

    private enum ImportAction {
        case skip
        case incrementalImport
        case resetAndImport
    }

    /// Parse JSONL file starting from a specific byte offset
    /// Skips the first incomplete line when offset > 0
    private func parseJSONLFileFromOffset(
        at url: URL,
        offset: Int64
    ) throws -> [(entry: UsageEntry, messageId: String, requestId: String)] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer { try? handle.close() }

        // Seek to offset
        if offset > 0 {
            try handle.seek(toOffset: UInt64(offset))
        }

        // Read remaining data
        guard let data = try handle.readToEnd(), !data.isEmpty else {
            return []
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var entries: [(entry: UsageEntry, messageId: String, requestId: String)] = []
        var isFirstLine = offset > 0  // Skip first line only if we seeked

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            // Skip first incomplete line after seeking
            if isFirstLine {
                isFirstLine = false
                continue
            }

            guard let lineData = line.data(using: .utf8),
                  let result = parseLogEntryWithIDs(data: lineData) else {
                continue
            }
            entries.append(result)
        }

        return entries
    }

    /// Parse JSONL file and return entries with their IDs for deduplication
    private func parseJSONLFileWithIDs(at url: URL) throws -> [(entry: UsageEntry, messageId: String, requestId: String)] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        var entries: [(entry: UsageEntry, messageId: String, requestId: String)] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let result = parseLogEntryWithIDs(data: lineData) else {
                continue
            }
            entries.append(result)
        }

        return entries
    }

    /// Parse a single log entry and return with IDs
    private func parseLogEntryWithIDs(data: Data) -> (entry: UsageEntry, messageId: String, requestId: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any],
              let timestampString = json["timestamp"] as? String,
              let timestamp = isoFormatter.date(from: timestampString) ?? isoFormatterNoFraction.date(from: timestampString) else {
            return nil
        }

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

        let fallbackId = fallbackIdentifier(for: data)
        let messageId = (message["id"] as? String) ?? fallbackId
        let requestId = (json["requestId"] as? String) ?? (json["request_id"] as? String) ?? fallbackId

        let entry = UsageEntry(
            model: model,
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            timestamp: timestamp
        )

        return (entry, messageId, requestId)
    }

    private func computeSnapshot() async throws -> TokenUsageSnapshot {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let last30DaysStart = Calendar.current.date(byAdding: .day, value: -30, to: todayStart)!
        let fileCutoff = Calendar.current.date(byAdding: .day, value: -31, to: todayStart)!

        // Load only files modified in last 31 days
        let jsonlFiles = try await self.loadAllJSONLFiles(modifiedAfter: fileCutoff)
        let jsonlFileSet = Set(jsonlFiles)

        // Determine which files changed since last scan
        let (changed, unchanged) = self.filesNeedingUpdate(jsonlFiles)

        // If no files changed and we have a cached snapshot, check if still valid
        if changed.isEmpty, let cached = self.lastSnapshot {
            // Invalidate cache if day boundary crossed (today's data would be stale)
            let cachedDayStart = Calendar.current.startOfDay(for: cached.fetchedAt)
            if cachedDayStart == todayStart {
                return cached  // Same day - cache is valid
            }
            // Day changed - need to recompute "today" aggregations
        }

        // Collect entries: reuse cached for unchanged files, parse changed files
        var allEntries: [UsageEntry] = []

        // Add cached entries from unchanged files
        for file in unchanged {
            if let entries = cachedEntriesByFile[file] {
                allEntries.append(contentsOf: entries.filter { $0.timestamp >= last30DaysStart })
            }
        }

        // Parse changed files and cache results
        // Use partial success - continue processing even if individual files fail
        var parseErrors: [URL: Error] = [:]
        for file in changed {
            do {
                let entries = try parseJSONLFile(at: file, cutoff: last30DaysStart)
                cachedEntriesByFile[file] = entries
                allEntries.append(contentsOf: entries)
            } catch {
                // Log error but continue with other files
                parseErrors[file] = error
                Logger.tokenUsage.warning("Failed to parse \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // If ALL files failed, throw an error
        if !changed.isEmpty && parseErrors.count == changed.count && allEntries.isEmpty {
            throw TokenUsageError.fileReadError(parseErrors.values.first!)
        }

        // Log partial success if some files failed
        if !parseErrors.isEmpty {
            Logger.tokenUsage.info("Partial success: \(changed.count - parseErrors.count)/\(changed.count) files parsed")
        }

        // Remove stale files from cache
        for file in Set(cachedEntriesByFile.keys).subtracting(jsonlFileSet) {
            cachedEntriesByFile.removeValue(forKey: file)
        }

        // Aggregate summaries
        let todayEntries = allEntries.filter { $0.timestamp >= todayStart }

        var byModel: [String: TokenCount] = [:]
        for entry in allEntries {
            let existing = byModel[entry.model] ?? .zero
            byModel[entry.model] = existing + entry.tokens
        }

        let snapshot = TokenUsageSnapshot(
            today: self.aggregateSummary(entries: todayEntries, period: .today),
            last30Days: self.aggregateSummary(entries: allEntries, period: .last30Days),
            byModel: byModel,
            fetchedAt: now
        )

        // Update file state and cache
        self.updateFileState(for: jsonlFiles)
        self.lastSnapshot = snapshot

        return snapshot
    }

    // MARK: - Private Methods

    private func loadAllJSONLFiles(modifiedAfter cutoffDate: Date) async throws -> [URL] {
        var jsonlFiles: [URL] = []
        for directory in Constants.claudeProjectsDirectories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let files = try findJSONLFiles(in: directory, modifiedAfter: cutoffDate)
            jsonlFiles.append(contentsOf: files)
        }
        return jsonlFiles
    }

    private func filesNeedingUpdate(_ files: [URL]) -> (changed: [URL], unchanged: [URL]) {
        var changed: [URL] = []
        var unchanged: [URL] = []
        for url in files {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if fileState[url] != mtime {
                changed.append(url)
            } else {
                unchanged.append(url)
            }
        }
        return (changed, unchanged)
    }

    private func updateFileState(for files: [URL]) {
        for url in files {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            fileState[url] = mtime
        }
    }

    private func findJSONLFiles(in directory: URL, modifiedAfter cutoffDate: Date) throws -> [URL] {
        var jsonlFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modDate >= cutoffDate {
                jsonlFiles.append(fileURL)
            }
        }

        return jsonlFiles
    }

    private func parseJSONLFile(at url: URL, cutoff: Date?) throws -> [UsageEntry] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        var entries: [UsageEntry] = []
        var processedHashes = Set<String>()

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let result = parseLogEntry(data: lineData, cutoff: cutoff) else {
                continue
            }

            // Deduplicate by message.id + requestId (same approach as ccusage)
            // Streaming responses log multiple entries per API call with the same IDs
            if let hash = result.uniqueHash {
                if processedHashes.contains(hash) {
                    continue // Skip duplicate message
                }
                processedHashes.insert(hash)
            }

            entries.append(result.entry)
        }
        return entries
    }

    /// Creates a unique hash from message.id and requestId for deduplication
    /// Returns nil if either field is missing (matches ccusage behavior)
    private func createUniqueHash(messageId: String?, requestId: String?) -> String? {
        guard let messageId, let requestId else {
            return nil
        }
        return "\(messageId):\(requestId)"
    }

    private func parseLogEntry(data: Data, cutoff: Date?) -> (entry: UsageEntry, uniqueHash: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any],
              let timestampString = json["timestamp"] as? String,
              let timestamp = isoFormatter.date(from: timestampString) ?? isoFormatterNoFraction.date(from: timestampString) else {
            return nil
        }

        if let cutoff, timestamp < cutoff {
            return nil
        }

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

        // Extract message.id and requestId for deduplication (same as ccusage)
        let messageId = message["id"] as? String
        let requestId = (json["requestId"] as? String) ?? (json["request_id"] as? String)
        let uniqueHash = createUniqueHash(messageId: messageId, requestId: requestId)

        let entry = UsageEntry(
            model: model,
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            timestamp: timestamp
        )

        return (entry, uniqueHash)
    }

    private func fallbackIdentifier(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "log-\(hex)"
    }

    private func aggregateSummary(entries: [UsageEntry], period: UsagePeriod) -> TokenUsageSummary {
        var totalTokens = TokenCount.zero
        var totalCost = 0.0

        for entry in entries {
            totalTokens = totalTokens + entry.tokens
            if let rates = ModelPricing.rates(for: entry.model) {
                let cost = calculateCost(tokens: entry.tokens, rates: rates)
                totalCost += cost
            }
        }

        return TokenUsageSummary(
            tokens: totalTokens,
            costUSD: totalCost,
            period: period
        )
    }

    private func calculateCost(tokens: TokenCount, rates: ModelPricing.Rates) -> Double {
        let inputCost = Double(tokens.inputTokens) * rates.inputPerMTok / 1_000_000
        let outputCost = Double(tokens.outputTokens) * rates.outputPerMTok / 1_000_000
        let cacheWriteCost = Double(tokens.cacheCreationTokens) * rates.cacheWritePerMTok / 1_000_000
        let cacheReadCost = Double(tokens.cacheReadTokens) * rates.cacheReadPerMTok / 1_000_000

        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }
}
#endif
