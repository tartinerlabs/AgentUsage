//
//  CodexLogSource.swift
//  AgentUsage
//
//  Token/cost usage from OpenAI Codex CLI rollout logs.
//

#if os(macOS)
import Foundation
import AgentUsageKit

/// Per-refresh parser metrics used by regression tests and local profiling.
nonisolated struct CodexLogSourceDiagnostics: Equatable, Sendable {
    var discoveredFileCount = 0
    var parsedFileCount = 0
    var cacheHitCount = 0
    var bytesRead = 0
    var maximumBufferedBytes = 0
}

/// Reads Codex CLI session rollout logs (`~/.codex/sessions/<y>/<m>/<d>/rollout-*.jsonl`).
///
/// Each rollout file is one session. Token usage lives in `event_msg` payloads of
/// type `token_count` (`info.total_token_usage`, cumulative for the session). We
/// take the last such event per file and emit a single entry, attributed to the
/// session's most recent `turn_context.model`.
actor CodexLogSource: UsageLogSource {
    nonisolated let provider: Provider = .codex

    private struct FileFingerprint: Equatable, Sendable {
        let size: Int64
        let modificationDate: Date
    }

    private struct RolloutFile: Sendable {
        let url: URL
        let fingerprint: FileFingerprint
    }

    private struct CachedRollout: Sendable {
        let fingerprint: FileFingerprint
        let entry: ProviderUsageEntry?
    }

    private struct ParseResult: Sendable {
        let entry: ProviderUsageEntry?
        let bytesRead: Int
        let maximumBufferedBytes: Int

        static let empty = ParseResult(entry: nil, bytesRead: 0, maximumBufferedBytes: 0)
    }

    private let fileManager = FileManager.default
    private let directories: [URL]
    private let readChunkSize: Int
    private var cachedRollouts: [URL: CachedRollout] = [:]
    private var diagnostics = CodexLogSourceDiagnostics()

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(
        directories: [URL] = Constants.codexSessionsDirectories,
        readChunkSize: Int = 64 * 1024
    ) {
        precondition(readChunkSize > 0)
        self.directories = directories
        self.readChunkSize = readChunkSize
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        let files = rolloutFiles(modifiedAfter: since)
        let currentURLs = Set(files.map(\.url))
        var nextDiagnostics = CodexLogSourceDiagnostics(discoveredFileCount: files.count)
        var entries: [ProviderUsageEntry] = []
        entries.reserveCapacity(files.count)

        for file in files {
            let entry: ProviderUsageEntry?
            if let cached = cachedRollouts[file.url],
               cached.fingerprint == file.fingerprint {
                nextDiagnostics.cacheHitCount += 1
                entry = cached.entry
            } else {
                let result = parseRollout(file)
                nextDiagnostics.parsedFileCount += 1
                nextDiagnostics.bytesRead += result.bytesRead
                nextDiagnostics.maximumBufferedBytes = max(
                    nextDiagnostics.maximumBufferedBytes,
                    result.maximumBufferedBytes
                )
                cachedRollouts[file.url] = CachedRollout(
                    fingerprint: file.fingerprint,
                    entry: result.entry
                )
                entry = result.entry
            }

            if let entry, entry.timestamp >= since {
                entries.append(entry)
            }
        }

        cachedRollouts = cachedRollouts.filter { currentURLs.contains($0.key) }
        diagnostics = nextDiagnostics
        return entries
    }

    /// Latest per-fetch diagnostics. Actor isolation keeps these consistent with the cache.
    func latestDiagnostics() -> CodexLogSourceDiagnostics {
        diagnostics
    }

    // MARK: - File discovery

    private func rolloutFiles(modifiedAfter cutoff: Date) -> [RolloutFile] {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        var result: [RolloutFile] = []

        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsHiddenFiles]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-"),
                      let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate,
                      modificationDate >= cutoff else { continue }

                result.append(
                    RolloutFile(
                        url: url,
                        fingerprint: FileFingerprint(
                            size: Int64(values.fileSize ?? 0),
                            modificationDate: modificationDate
                        )
                    )
                )
            }
        }

        return result
    }

    // MARK: - Reverse parsing

    /// Scans complete JSONL records from the end of the file. Codex appends the
    /// cumulative token count and current model near the tail, so unchanged history
    /// never needs to be loaded or decoded.
    private func parseRollout(_ file: RolloutFile) -> ParseResult {
        guard file.fingerprint.size > 0,
              let handle = try? FileHandle(forReadingFrom: file.url) else {
            return .empty
        }
        defer { try? handle.close() }

        var latestModel: String?
        var latestTokenUsage: [String: Any]?
        var latestTimestamp: Date?
        var position = UInt64(file.fingerprint.size)
        var pendingLineFragments: [Data] = []
        var pendingLineByteCount = 0
        var bytesRead = 0
        var maximumBufferedBytes = 0

        do {
            while position > 0,
                  !hasCompleteResult(
                    model: latestModel,
                    tokenUsage: latestTokenUsage,
                    timestamp: latestTimestamp
                  ) {
                let count = min(readChunkSize, Int(position))
                position -= UInt64(count)
                try handle.seek(toOffset: position)

                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                    break
                }
                bytesRead += chunk.count

                maximumBufferedBytes = max(
                    maximumBufferedBytes,
                    pendingLineByteCount + chunk.count
                )

                var lineEnd = chunk.endIndex
                while let newline = chunk[..<lineEnd].lastIndex(of: 0x0A) {
                    let lineStart = chunk.index(after: newline)
                    if lineStart < lineEnd || pendingLineByteCount > 0 {
                        if pendingLineByteCount == 0 {
                            inspect(
                                line: chunk[lineStart..<lineEnd],
                                latestModel: &latestModel,
                                latestTokenUsage: &latestTokenUsage,
                                latestTimestamp: &latestTimestamp
                            )
                        } else {
                            let line = assembleLine(
                                prefix: chunk[lineStart..<lineEnd],
                                fragments: &pendingLineFragments,
                                fragmentByteCount: &pendingLineByteCount
                            )
                            maximumBufferedBytes = max(maximumBufferedBytes, line.count)
                            inspect(
                                line: line,
                                latestModel: &latestModel,
                                latestTokenUsage: &latestTokenUsage,
                                latestTimestamp: &latestTimestamp
                            )
                        }
                    }

                    if hasCompleteResult(
                        model: latestModel,
                        tokenUsage: latestTokenUsage,
                        timestamp: latestTimestamp
                    ) {
                        break
                    }
                    lineEnd = newline
                }

                if hasCompleteResult(
                    model: latestModel,
                    tokenUsage: latestTokenUsage,
                    timestamp: latestTimestamp
                ) {
                    break
                }

                if lineEnd > chunk.startIndex {
                    let fragment = Data(chunk[..<lineEnd])
                    pendingLineByteCount += fragment.count
                    pendingLineFragments.append(fragment)
                    maximumBufferedBytes = max(maximumBufferedBytes, pendingLineByteCount)
                }

                if position == 0, pendingLineByteCount > 0 {
                    let line = assembleLine(
                        prefix: Data(),
                        fragments: &pendingLineFragments,
                        fragmentByteCount: &pendingLineByteCount
                    )
                    maximumBufferedBytes = max(maximumBufferedBytes, line.count)
                    inspect(
                        line: line,
                        latestModel: &latestModel,
                        latestTokenUsage: &latestTokenUsage,
                        latestTimestamp: &latestTimestamp
                    )
                }
            }
        } catch {
            return ParseResult(
                entry: nil,
                bytesRead: bytesRead,
                maximumBufferedBytes: maximumBufferedBytes
            )
        }

        guard let total = latestTokenUsage else {
            return ParseResult(
                entry: nil,
                bytesRead: bytesRead,
                maximumBufferedBytes: maximumBufferedBytes
            )
        }

        // Codex: total = input + output; `input` includes cached, `output` includes reasoning.
        // Split into disjoint components so totals/cost don't double-count.
        let rawInput = total["input_tokens"] as? Int ?? 0
        let cachedInput = total["cached_input_tokens"] as? Int ?? 0
        let rawOutput = total["output_tokens"] as? Int ?? 0
        let reasoning = total["reasoning_output_tokens"] as? Int ?? 0
        let tokens = TokenCount(
            inputTokens: max(0, rawInput - cachedInput),
            outputTokens: max(0, rawOutput - reasoning),
            cacheCreationTokens: 0,
            cacheReadTokens: cachedInput,
            reasoningTokens: reasoning
        )

        let entry = ProviderUsageEntry(
            provider: .codex,
            model: latestModel ?? "gpt-5-codex",
            pricingProviderKey: "openai",
            tokens: tokens,
            timestamp: latestTimestamp ?? file.fingerprint.modificationDate,
            dedupKey: "codex:\(Self.sessionIdentifier(for: file.url))"
        )
        return ParseResult(
            entry: entry,
            bytesRead: bytesRead,
            maximumBufferedBytes: maximumBufferedBytes
        )
    }

    /// Joins one cross-chunk line exactly once. Fragments are stored newest-first
    /// while scanning backwards, so removing them from the end restores file order.
    private func assembleLine(
        prefix: Data,
        fragments: inout [Data],
        fragmentByteCount: inout Int
    ) -> Data {
        var line = Data()
        line.reserveCapacity(prefix.count + fragmentByteCount)
        line.append(prefix)
        while let fragment = fragments.popLast() {
            line.append(fragment)
        }
        fragmentByteCount = 0
        return line
    }

    private func hasCompleteResult(
        model: String?,
        tokenUsage: [String: Any]?,
        timestamp: Date?
    ) -> Bool {
        model != nil && tokenUsage != nil && timestamp != nil
    }

    /// Inspects only records that could contain data we still need. The substring
    /// checks avoid decoding large prompt/tool-output records as JSON.
    private func inspect(
        line: Data,
        latestModel: inout String?,
        latestTokenUsage: inout [String: Any]?,
        latestTimestamp: inout Date?
    ) {
        let mayContainModel = latestModel == nil && line.range(of: Self.turnContextMarker) != nil
        let mayContainTokens = (latestTokenUsage == nil || latestTimestamp == nil)
            && line.range(of: Self.tokenCountMarker) != nil
        guard mayContainModel || mayContainTokens,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return }

        let payload = json["payload"] as? [String: Any]
        if mayContainModel,
           type == "turn_context",
           let model = payload?["model"] as? String,
           !model.isEmpty {
            latestModel = model
        }

        guard mayContainTokens,
              type == "event_msg",
              payload?["type"] as? String == "token_count",
              let info = payload?["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else { return }

        if latestTokenUsage == nil {
            latestTokenUsage = total
        }
        if latestTimestamp == nil,
           let timestamp = json["timestamp"] as? String {
            latestTimestamp = isoFormatter.date(from: timestamp)
                ?? isoFormatterNoFraction.date(from: timestamp)
        }
    }

    private static let turnContextMarker = Data(#""turn_context""#.utf8)
    private static let tokenCountMarker = Data(#""token_count""#.utf8)

    /// Rollout filenames end in the session UUID. Using it avoids reading the
    /// potentially multi-megabyte `session_meta` record at the start of the file.
    private static func sessionIdentifier(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let candidate = String(stem.suffix(36))
        return UUID(uuidString: candidate) == nil ? stem : candidate.lowercased()
    }
}
#endif
