//
//  TokenUsageService.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import AgentUsageKit
import OSLog
import CryptoKit

actor TokenUsageService: TokenUsageServiceProtocol {
    private let fileManager = FileManager.default

    /// Additional providers (Codex, OpenCode, …) merged into the snapshot.
    /// Claude is read directly by this service.
    private let extraSources: [any UsageLogSource]

    init(extraSources: [any UsageLogSource] = []) {
        self.extraSources = extraSources
    }

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

    /// Full per-provider detail (today/yesterday/30-day, per-model, daily trend)
    /// for the extra (non-Claude) sources.
    ///
    /// Claude's detail is assembled from the SwiftData path; this avoids
    /// re-parsing Claude logs just to surface Codex/OpenCode totals.
    func fetchExtraProviderDetails(since: Date) async -> [Provider: ProviderDetail] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        var entriesByProvider: [Provider: [ProviderUsageEntry]] = [:]
        for source in extraSources {
            guard let entries = try? await source.fetchEntries(since: since) else { continue }
            for entry in entries {
                entriesByProvider[entry.provider, default: []].append(entry)
            }
        }

        var result: [Provider: ProviderDetail] = [:]
        for (provider, entries) in entriesByProvider {
            let todayEntries = entries.filter { $0.timestamp >= todayStart }
            let yesterdayEntries = entries.filter { $0.timestamp >= yesterdayStart && $0.timestamp < todayStart }

            var byModel: [String: TokenCount] = [:]
            for entry in entries {
                byModel[entry.model] = (byModel[entry.model] ?? .zero) + entry.tokens
            }

            result[provider] = ProviderDetail(
                today: aggregateSummary(entries: todayEntries, period: .today),
                yesterday: aggregateSummary(entries: yesterdayEntries, period: .today),
                last30Days: aggregateSummary(entries: entries, period: .last30Days),
                byModel: byModel,
                dailyCosts: dailyCosts(from: entries, days: 30, todayStart: todayStart, calendar: calendar)
            )
        }
        return result
    }

    /// Bucket entries into a `days`-length daily cost series (oldest → newest).
    private func dailyCosts(from entries: [ProviderUsageEntry], days: Int, todayStart: Date, calendar: Calendar) -> [Double] {
        var byDay: [Date: Double] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            byDay[day, default: 0] += cost(for: entry)
        }
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            return byDay[day] ?? 0
        }
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

        let isFirstLine = offset > 0  // Skip first line only if we seeked
        let parsed = parseJSONLines(content, skippingFirstLine: isFirstLine)

        return Self.deduplicate(parsed).map(idTuple(from:))
    }

    /// Parse JSONL file and return entries with their IDs for deduplication
    private func parseJSONLFileWithIDs(at url: URL) throws -> [(entry: UsageEntry, messageId: String, requestId: String)] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        let parsed = parseJSONLines(content)

        return Self.deduplicate(parsed).map(idTuple(from:))
    }

    /// Map a deduped entry to the import tuple, substituting synthetic ids when message/request ids are absent.
    private func idTuple(from fields: ParsedFields) -> (entry: UsageEntry, messageId: String, requestId: String) {
        (
            entry: fields.entry,
            messageId: fields.messageId ?? fields.fallbackId,
            requestId: fields.requestId ?? fields.fallbackId
        )
    }

    /// Common fields parsed from one JSONL assistant line, before dedup.
    struct ParsedFields {
        let entry: UsageEntry
        let messageId: String?
        let requestId: String?
        let isSidechain: Bool
        /// SHA-based synthetic id for entries missing message/request ids (keeps SwiftData ids unique).
        let fallbackId: String
    }

    /// Parse all valid assistant records from JSONL content while ignoring malformed
    /// and unrelated lines. Internal for deterministic regression coverage.
    func parseJSONLines(
        _ content: String,
        skippingFirstLine: Bool = false,
        cutoff: Date? = nil
    ) -> [ParsedFields] {
        var parsed: [ParsedFields] = []
        var shouldSkipLine = skippingFirstLine

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            if shouldSkipLine {
                shouldSkipLine = false
                continue
            }
            guard let lineData = line.data(using: .utf8),
                  let fields = parseCommonFields(data: lineData),
                  cutoff.map({ fields.entry.timestamp >= $0 }) ?? true else {
                continue
            }
            parsed.append(fields)
        }
        return parsed
    }

    /// Parse a single assistant log line into common fields (tokens incl. 1h cache, fast mode, sidechain).
    private func parseCommonFields(data: Data) -> ParsedFields? {
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
        // 1h ephemeral cache (billed at 2× input). Subset of cache_creation_input_tokens.
        let cacheCreation1hTokens = (usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? Int ?? 0
        let fastMode = (usage["speed"] as? String) == "fast"
        let isSidechain = json["isSidechain"] as? Bool ?? false

        let entry = UsageEntry(
            model: model,
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreation1hTokens: cacheCreation1hTokens
            ),
            timestamp: timestamp,
            fastMode: fastMode
        )

        return ParsedFields(
            entry: entry,
            messageId: message["id"] as? String,
            requestId: (json["requestId"] as? String) ?? (json["request_id"] as? String),
            isSidechain: isSidechain,
            fallbackId: fallbackIdentifier(for: data)
        )
    }

    /// Dedup keys for one entry: the exact `messageId:requestId` plus a `messageId`-only fallback that
    /// catches sidechain replays (same message, fresh requestId). Empty when no messageId — cannot dedup.
    nonisolated static func dedupKeys(messageId: String?, requestId: String?) -> [String] {
        guard let messageId else { return [] }
        guard let requestId else { return ["msg:\(messageId)"] }
        return ["\(messageId):\(requestId)", "msg:\(messageId)"]
    }

    /// Sidechain-aware dedup (ported from ccusage): on collision keep the better record —
    /// a non-sidechain entry beats a sidechain one; otherwise the higher total-token entry wins.
    nonisolated static func deduplicate(_ parsed: [ParsedFields]) -> [ParsedFields] {
        var slotForKey: [String: Int] = [:]
        var result: [ParsedFields] = []

        for candidate in parsed {
            let keys = dedupKeys(messageId: candidate.messageId, requestId: candidate.requestId)
            guard !keys.isEmpty else {
                result.append(candidate) // no ids → cannot dedup, keep
                continue
            }

            if let slot = keys.lazy.compactMap({ slotForKey[$0] }).first {
                if shouldReplaceDeduped(existing: result[slot], candidate: candidate) {
                    result[slot] = candidate
                }
                for key in keys { slotForKey[key] = slot }
            } else {
                let slot = result.count
                result.append(candidate)
                for key in keys { slotForKey[key] = slot }
            }
        }

        return result
    }

    nonisolated static func shouldReplaceDeduped(existing: ParsedFields, candidate: ParsedFields) -> Bool {
        if existing.isSidechain != candidate.isSidechain {
            return existing.isSidechain && !candidate.isSidechain
        }
        return candidate.entry.tokens.totalTokens > existing.entry.tokens.totalTokens
    }

    private func computeSnapshot() async throws -> TokenUsageSnapshot {
        await LiteLLMPricingCache.shared.refreshIfNeeded()

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

        // Unify Claude entries with any additional providers (Codex, OpenCode, …)
        var unified: [ProviderUsageEntry] = allEntries.enumerated().map { index, entry in
            ProviderUsageEntry(
                provider: .claude,
                model: entry.model,
                pricingProviderKey: "anthropic",
                tokens: entry.tokens,
                timestamp: entry.timestamp,
                dedupKey: "claude:\(index)",  // Claude entries are already deduped during parse
                fastMode: entry.fastMode
            )
        }

        for source in extraSources {
            do {
                let entries = try await source.fetchEntries(since: last30DaysStart)
                unified.append(contentsOf: entries)
            } catch {
                Logger.tokenUsage.warning("Source \(source.provider.rawValue) failed: \(error.localizedDescription)")
            }
        }

        // Deduplicate across sources by provider-scoped key
        var seen = Set<String>()
        unified = unified.filter { seen.insert($0.dedupKey).inserted }

        // Aggregate summaries
        let todayEntries = unified.filter { $0.timestamp >= todayStart }

        var byModel: [String: TokenCount] = [:]
        for entry in unified {
            let existing = byModel[entry.model] ?? .zero
            byModel[entry.model] = existing + entry.tokens
        }

        var byProvider: [Provider: TokenUsageSummary] = [:]
        for provider in Set(unified.map(\.provider)) {
            let entries = unified.filter { $0.provider == provider }
            byProvider[provider] = self.aggregateSummary(entries: entries, period: .last30Days)
        }

        let snapshot = TokenUsageSnapshot(
            today: self.aggregateSummary(entries: todayEntries, period: .today),
            last30Days: self.aggregateSummary(entries: unified, period: .last30Days),
            byModel: byModel,
            byProvider: byProvider,
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

        let parsed = parseJSONLines(content, cutoff: cutoff)

        // Sidechain-aware dedup (ccusage approach): collapse streaming duplicates and sidechain replays.
        return Self.deduplicate(parsed).map(\.entry)
    }

    private func fallbackIdentifier(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "log-\(hex)"
    }

    private func aggregateSummary(entries: [ProviderUsageEntry], period: UsagePeriod) -> TokenUsageSummary {
        var totalTokens = TokenCount.zero
        var totalCost = 0.0

        for entry in entries {
            totalTokens = totalTokens + entry.tokens
            totalCost += cost(for: entry)
        }

        return TokenUsageSummary(
            tokens: totalTokens,
            costUSD: totalCost,
            period: period
        )
    }

    /// Cost for an entry: trust a provider-precomputed value, else compute via `ModelPricing`.
    private func cost(for entry: ProviderUsageEntry) -> Double {
        if let precomputed = entry.precomputedCostUSD { return precomputed }
        return ModelPricing.costUSD(
            provider: entry.pricingProviderKey,
            model: entry.model,
            inputTokens: entry.tokens.inputTokens,
            outputTokens: entry.tokens.outputTokens,
            cacheReadTokens: entry.tokens.cacheReadTokens,
            cacheWriteTokens: entry.tokens.cacheCreationTokens,
            reasoningTokens: entry.tokens.reasoningTokens,
            cacheWrite1hTokens: entry.tokens.cacheCreation1hTokens,
            fastMode: entry.fastMode
        ) ?? 0
    }
}
#endif
