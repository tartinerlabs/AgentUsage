//
//  TokenUsageService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation

actor TokenUsageService {
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

        // If no files changed and we have a cached snapshot, return it
        if changed.isEmpty, let cached = self.lastSnapshot {
            return cached
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
        for file in changed {
            let entries = try parseJSONLFile(at: file, cutoff: last30DaysStart)
            cachedEntriesByFile[file] = entries
            allEntries.append(contentsOf: entries)
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
              let timestamp = isoFormatter.date(from: timestampString) else {
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
        let requestId = json["requestId"] as? String
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

    private func aggregateSummary(entries: [UsageEntry], period: TokenUsageSummary.UsagePeriod) -> TokenUsageSummary {
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
