//
//  TokenUsageService.swift
//  ClaudeMeter
//

import Foundation

actor TokenUsageService {
    private let fileManager = FileManager.default

    // Reentrancy guard: reuse in-flight fetch instead of starting a new one
    private var inFlightTask: Task<TokenUsageSnapshot, Error>?

    // Caching and state tracking
    private var lastSnapshot: TokenUsageSnapshot?
    private var fileState: [URL: Date] = [:]

    // Reuse a single formatter
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fetch token usage from local JSONL logs
    func fetchUsage() async throws -> TokenUsageSnapshot {
        if let task = inFlightTask {
            #if DEBUG
            print("⏳ Reusing in-flight token usage fetch")
            #endif
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
        let last7DaysStart = Calendar.current.date(byAdding: .day, value: -7, to: todayStart)!
        let cutoff = last7DaysStart

        // Load file list
        let jsonlFiles = try await self.loadAllJSONLFiles()

        // Determine which files changed since last scan
        let (changed, unchanged) = self.filesNeedingUpdate(jsonlFiles)

        // If no files changed and we have a snapshot, return it immediately
        if changed.isEmpty, let cached = self.lastSnapshot {
            return cached
        }

        // Parse changed files concurrently and combine with unchanged by reusing previous aggregates if available
        let changedEntries = try await self.parseJSONLFilesConcurrently(changed, cutoff: cutoff)

        // For unchanged files, we avoid re-parsing to save time by relying on previous snapshot
        // We still need all entries to compute today and last7Days summaries. If no cached snapshot, parse all.
        var allEntries: [UsageEntry]
        if let _ = self.lastSnapshot, !unchanged.isEmpty {
            let unchangedEntries = try await self.parseJSONLFilesConcurrently(unchanged, cutoff: cutoff)
            allEntries = changedEntries + unchangedEntries
        } else {
            let allParsed = try await self.parseJSONLFilesConcurrently(jsonlFiles, cutoff: cutoff)
            allEntries = allParsed
        }

        // Aggregate summaries
        let todayEntries = allEntries.filter { $0.timestamp >= todayStart }
        let last7DaysEntries = allEntries // already filtered by cutoff during parsing

        // Aggregate by model for last 7 days
        var byModel: [String: TokenCount] = [:]
        for entry in last7DaysEntries {
            let existing = byModel[entry.model] ?? .zero
            byModel[entry.model] = existing + entry.tokens
        }

        let snapshot = TokenUsageSnapshot(
            today: self.aggregateSummary(entries: todayEntries, period: .today),
            last7Days: self.aggregateSummary(entries: last7DaysEntries, period: .last7Days),
            byModel: byModel,
            fetchedAt: now
        )

        // Update file state and cache
        self.updateFileState(for: jsonlFiles)
        self.lastSnapshot = snapshot

        return snapshot
    }

    // MARK: - Private Methods

    private func loadAllJSONLFiles() async throws -> [URL] {
        var jsonlFiles: [URL] = []
        for directory in Constants.claudeProjectsDirectories {
            let exists = fileManager.fileExists(atPath: directory.path)
            #if DEBUG
            print("📂 Checking \(directory.path): exists=\(exists)")
            #endif
            guard exists else { continue }

            let files = try findJSONLFiles(in: directory)
            #if DEBUG
            print("📄 Found \(files.count) JSONL files in \(directory.lastPathComponent)")
            #endif
            jsonlFiles.append(contentsOf: files)
        }
        #if DEBUG
        print("📄 Total JSONL files: \(jsonlFiles.count)")
        #endif
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

    private func findJSONLFiles(in directory: URL) throws -> [URL] {
        var jsonlFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }

        return jsonlFiles
    }

    private func parseJSONLFilesConcurrently(_ files: [URL], cutoff: Date?) async throws -> [UsageEntry] {
        try await withThrowingTaskGroup(of: [UsageEntry].self) { group in
            for file in files {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return try await self.parseJSONLFile(at: file, cutoff: cutoff)
                }
            }
            var combined: [UsageEntry] = []
            for try await entries in group {
                combined.append(contentsOf: entries)
            }
            return combined
        }
    }

    private func parseJSONLFile(at url: URL, cutoff: Date?) throws -> [UsageEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var entries: [UsageEntry] = []

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024)
            if let chunk, !chunk.isEmpty {
                buffer.append(chunk)
                // Process complete lines
                while let range = buffer.firstRange(of: Data([0x0A])) { // newline
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    guard !lineData.isEmpty else { continue }
                    if let entry = parseLogEntry(data: lineData, cutoff: cutoff) {
                        entries.append(entry)
                    }
                }
            } else {
                break
            }
        }

        // Process any remaining data as the last line (no trailing newline)
        if !buffer.isEmpty, let entry = parseLogEntry(data: buffer, cutoff: cutoff) {
            entries.append(entry)
        }

        return entries
    }

    private func parseLogEntry(data: Data, cutoff: Date?) -> UsageEntry? {
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

        return UsageEntry(
            model: model,
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            timestamp: timestamp
        )
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
