//
//  GrokLogSource.swift
//  AgentUsage
//
//  Token/cost usage from Grok Build session directories.
//

#if os(macOS)
import Foundation
import AgentUsageKit

/// Per-refresh parser metrics used by regression tests.
nonisolated struct GrokLogSourceDiagnostics: Equatable, Sendable {
    var discoveredSessionCount = 0
    var parsedSessionCount = 0
    var cacheHitCount = 0
    var bytesRead = 0
}

/// Reads Grok Build sessions (`$GROK_HOME/sessions/<cwd>/<id>/`).
///
/// Grok does not log billable input/output tokens. `updates.jsonl` carries a
/// running context fill (`params._meta.totalTokens`) per streamed chunk. We
/// reconstruct a per-turn estimate: the first turn's starting fill is billed as
/// input, later turns as cache reads, and context growth during a turn as
/// output. `signals.json` `contextTokensUsed` is the fallback when the stream
/// has no token metadata.
actor GrokLogSource: UsageLogSource {
    nonisolated let provider: Provider = .grok

    private struct FileFingerprint: Equatable, Sendable {
        let size: Int64
        let modificationDate: Date
    }

    private struct SessionFingerprint: Equatable, Sendable {
        let summary: FileFingerprint
        let updates: FileFingerprint?
        let signals: FileFingerprint?
    }

    private struct SessionFiles: Sendable {
        let directory: URL
        let summaryURL: URL
        let updatesURL: URL
        let signalsURL: URL
        let fingerprint: SessionFingerprint
    }

    private struct CachedSession: Sendable {
        let fingerprint: SessionFingerprint
        let entry: ProviderUsageEntry?
    }

    private struct TurnAccumulator {
        var minTokens: Int
        var maxTokens: Int
        var turnStartMs: Int64
    }

    private let fileManager: FileManager
    private let directories: [URL]
    private let readChunkSize: Int
    private var cachedSessions: [URL: CachedSession] = [:]
    private var diagnostics = GrokLogSourceDiagnostics()

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
        directories: [URL] = Constants.grokSessionsDirectories,
        readChunkSize: Int = 64 * 1024,
        fileManager: FileManager = .default
    ) {
        precondition(readChunkSize > 0)
        self.directories = directories
        self.readChunkSize = readChunkSize
        self.fileManager = fileManager
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        let sessions = try sessionFiles(modifiedAfter: since)
        let currentURLs = Set(sessions.map(\.directory))
        var nextDiagnostics = GrokLogSourceDiagnostics(discoveredSessionCount: sessions.count)
        var entries: [ProviderUsageEntry] = []
        entries.reserveCapacity(sessions.count)

        for session in sessions {
            let entry: ProviderUsageEntry?
            if let cached = cachedSessions[session.directory],
               cached.fingerprint == session.fingerprint {
                nextDiagnostics.cacheHitCount += 1
                entry = cached.entry
            } else {
                let parsed = parseSession(session)
                nextDiagnostics.parsedSessionCount += 1
                nextDiagnostics.bytesRead += parsed.bytesRead
                cachedSessions[session.directory] = CachedSession(
                    fingerprint: session.fingerprint,
                    entry: parsed.entry
                )
                entry = parsed.entry
            }

            if let entry, entry.timestamp >= since {
                entries.append(entry)
            }
        }

        let retentionCutoff = Calendar.current.date(
            byAdding: .month,
            value: -13,
            to: Date()
        ) ?? since
        cachedSessions = cachedSessions.filter { url, cached in
            currentURLs.contains(url)
                || (cached.fingerprint.summary.modificationDate < since
                    && cached.fingerprint.summary.modificationDate >= retentionCutoff)
        }
        diagnostics = nextDiagnostics
        return entries
    }

    func latestDiagnostics() -> GrokLogSourceDiagnostics {
        diagnostics
    }

    // MARK: - Discovery

    private func sessionFiles(modifiedAfter cutoff: Date) throws -> [SessionFiles] {
        var result: [SessionFiles] = []
        var foundReadableDirectory = false
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]

        for directory in directories {
            do {
                _ = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                guard Self.isMissingDirectoryError(error) else {
                    throw UsageLogSourceError.unavailable
                }
                continue
            }

            var traversalFailed = false
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    traversalFailed = true
                    return false
                }
            ) else {
                throw UsageLogSourceError.unavailable
            }
            foundReadableDirectory = true

            for case let url as URL in enumerator {
                guard url.lastPathComponent == "summary.json",
                      let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true else { continue }

                let sessionDirectory = url.deletingLastPathComponent()
                let updatesURL = sessionDirectory.appendingPathComponent("updates.jsonl")
                let signalsURL = sessionDirectory.appendingPathComponent("signals.json")
                let summaryFingerprint = FileFingerprint(
                    size: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast
                )
                let updatesFingerprint = fingerprint(at: updatesURL, keys: resourceKeys)
                let signalsFingerprint = fingerprint(at: signalsURL, keys: resourceKeys)
                let latestModification = [
                    summaryFingerprint.modificationDate,
                    updatesFingerprint?.modificationDate,
                    signalsFingerprint?.modificationDate
                ].compactMap { $0 }.max() ?? summaryFingerprint.modificationDate

                guard latestModification >= cutoff else { continue }

                result.append(
                    SessionFiles(
                        directory: sessionDirectory,
                        summaryURL: url,
                        updatesURL: updatesURL,
                        signalsURL: signalsURL,
                        fingerprint: SessionFingerprint(
                            summary: summaryFingerprint,
                            updates: updatesFingerprint,
                            signals: signalsFingerprint
                        )
                    )
                )
            }

            guard !traversalFailed else {
                throw UsageLogSourceError.unavailable
            }
        }

        guard foundReadableDirectory else {
            throw UsageLogSourceError.unavailable
        }
        return result
    }

    private func fingerprint(at url: URL, keys: Set<URLResourceKey>) -> FileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else { return nil }
        return FileFingerprint(
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }

    private nonisolated static func isMissingDirectoryError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        guard cocoaError.domain == NSCocoaErrorDomain else { return false }
        return cocoaError.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoaError.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }

    // MARK: - Parsing

    private struct ParseResult {
        let entry: ProviderUsageEntry?
        let bytesRead: Int
    }

    private func parseSession(_ session: SessionFiles) -> ParseResult {
        guard let summaryData = try? Data(contentsOf: session.summaryURL),
              let summary = try? JSONSerialization.jsonObject(with: summaryData) as? [String: Any] else {
            return ParseResult(entry: nil, bytesRead: 0)
        }

        let info = summary["info"] as? [String: Any]
        let sessionID = (info?["id"] as? String)?.nonEmpty
            ?? session.directory.lastPathComponent
        let model = (summary["current_model_id"] as? String)?.nonEmpty
            ?? "grok-4.6"
        let timestamp = parseTimestamp(summary["updated_at"] as? String)
            ?? parseTimestamp(summary["last_active_at"] as? String)
            ?? session.fingerprint.summary.modificationDate
        let effortLevel = Self.normalizedEffortLevel(summary["reasoning_effort"])
        let isSubagentSession = Self.isSubagentSession(summary: summary, directory: session.directory)

        let stream = parseTokenStream(at: session.updatesURL)
        let tokens: TokenCount
        if stream.tokens.totalTokens > 0 {
            tokens = stream.tokens
        } else if let fallback = fallbackTokens(at: session.signalsURL) {
            tokens = fallback
        } else {
            tokens = .zero
        }

        let entry = ProviderUsageEntry(
            provider: .grok,
            model: model,
            pricingProviderKey: "xai",
            tokens: tokens,
            timestamp: timestamp,
            dedupKey: "grok:\(sessionID)",
            sessionID: sessionID,
            effortLevel: effortLevel,
            isSubagentSession: isSubagentSession
        )
        return ParseResult(entry: entry, bytesRead: summaryData.count + stream.bytesRead)
    }

    private func parseTokenStream(at url: URL) -> (tokens: TokenCount, bytesRead: Int) {
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return (.zero, 0)
        }
        defer { try? handle.close() }

        var turns: [String: TurnAccumulator] = [:]
        var turnOrder: [String] = []
        var pending = Data()
        var bytesRead = 0

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: readChunkSize) ?? Data()
            } catch {
                break
            }
            if chunk.isEmpty { break }
            bytesRead += chunk.count
            pending.append(chunk)

            var searchStart = pending.startIndex
            while let newline = pending[searchStart...].firstIndex(of: 0x0A) {
                let line = pending[searchStart..<newline]
                inspectTokenLine(Data(line), turns: &turns, turnOrder: &turnOrder)
                searchStart = pending.index(after: newline)
            }
            if searchStart > pending.startIndex {
                pending.removeSubrange(pending.startIndex..<searchStart)
            }
        }

        if !pending.isEmpty {
            inspectTokenLine(pending, turns: &turns, turnOrder: &turnOrder)
        }

        return (tokensFromTurns(turns, order: turnOrder), bytesRead)
    }

    private func inspectTokenLine(
        _ line: Data,
        turns: inout [String: TurnAccumulator],
        turnOrder: inout [String]
    ) {
        guard line.range(of: Self.totalTokensMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let params = json["params"] as? [String: Any],
              let meta = params["_meta"] as? [String: Any],
              let promptID = (meta["promptId"] as? String)?.nonEmpty,
              let totalTokens = Self.intValue(meta["totalTokens"]) else { return }

        let turnStartMs = Self.int64Value(meta["turnStartMs"]) ?? 0
        if var existing = turns[promptID] {
            existing.minTokens = min(existing.minTokens, totalTokens)
            existing.maxTokens = max(existing.maxTokens, totalTokens)
            if turnStartMs > 0 {
                existing.turnStartMs = existing.turnStartMs == 0
                    ? turnStartMs
                    : min(existing.turnStartMs, turnStartMs)
            }
            turns[promptID] = existing
        } else {
            turns[promptID] = TurnAccumulator(
                minTokens: totalTokens,
                maxTokens: totalTokens,
                turnStartMs: turnStartMs
            )
            turnOrder.append(promptID)
        }
    }

    private func tokensFromTurns(
        _ turns: [String: TurnAccumulator],
        order: [String]
    ) -> TokenCount {
        guard !turns.isEmpty else { return .zero }

        let sortedIDs = order.sorted { lhs, rhs in
            let left = turns[lhs]?.turnStartMs ?? 0
            let right = turns[rhs]?.turnStartMs ?? 0
            if left != right { return left < right }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }

        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        for (index, promptID) in sortedIDs.enumerated() {
            guard let turn = turns[promptID] else { continue }
            let growth = max(0, turn.maxTokens - turn.minTokens)
            outputTokens += growth
            if index == 0 {
                inputTokens += turn.minTokens
            } else {
                cacheReadTokens += turn.minTokens
            }
        }

        return TokenCount(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: 0,
            cacheReadTokens: cacheReadTokens
        )
    }

    private func fallbackTokens(at url: URL) -> TokenCount? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contextTokens = Self.intValue(json["contextTokensUsed"]),
              contextTokens > 0 else { return nil }
        return TokenCount(
            inputTokens: contextTokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = isoFormatter.date(from: raw) { return date }
        if let date = isoFormatterNoFraction.date(from: raw) { return date }
        if let dot = raw.lastIndex(of: "."), raw.hasSuffix("Z") {
            let fractionStart = raw.index(after: dot)
            let fractionEnd = raw.index(before: raw.endIndex)
            let fraction = raw[fractionStart..<fractionEnd]
            let rebuilt = String(raw[..<fractionStart]) + String(fraction.prefix(3)) + "Z"
            return isoFormatter.date(from: rebuilt)
        }
        return nil
    }

    private nonisolated static func isSubagentSession(
        summary: [String: Any],
        directory: URL
    ) -> Bool {
        if directory.pathComponents.contains("subagents") { return true }
        let kind = (summary["session_kind"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return kind == "subagent"
    }

    private nonisolated static func normalizedEffortLevel(_ value: Any?) -> EffortLevel? {
        guard let rawValue = value as? String else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : EffortLevel(rawValue: normalized)
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as Int64: Int(number)
        case let number as Double: Int(number)
        case let number as NSNumber: number.intValue
        default: nil
        }
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as Int64: number
        case let number as Int: Int64(number)
        case let number as Double: Int64(number)
        case let number as NSNumber: number.int64Value
        default: nil
        }
    }

    private static let totalTokensMarker = Data(#""totalTokens""#.utf8)
}

private nonisolated extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
