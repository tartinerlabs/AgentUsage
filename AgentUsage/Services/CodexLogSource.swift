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
/// Each rollout file is one session. Newer Codex appends a `token_usage_record` after
/// every completed response, whose `thread_token_usage` is cumulative for the session.
/// Older rollouts only have `event_msg` payloads of type `token_count`
/// (`info.total_token_usage`), which leave out remote compaction. We take the newest
/// total per file and emit a single entry, attributed to the session's most recent
/// `turn_context.model`.
///
/// A fork, or the new rollout that reverting a thread starts, begins its running
/// totals at the source thread's totals. The source's rollout already counts that
/// usage, so it is subtracted from the fork's or revert's entry.
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

    private struct ReadStats: Sendable {
        var bytesRead = 0
        var maximumBufferedBytes = 0

        mutating func buffered(_ byteCount: Int) {
            maximumBufferedBytes = max(maximumBufferedBytes, byteCount)
        }
    }

    private struct ParseResult: Sendable {
        let entry: ProviderUsageEntry?
        let reads: ReadStats

        static let empty = ParseResult(entry: nil, reads: ReadStats())
    }

    /// The source rollout prefix a Referenced fork or a reverted thread continues from
    /// (`session_meta.history_base`). Its records stay in that rollout.
    private struct HistoryBase: Sendable {
        let rolloutID: String
        let endByteOffset: UInt64
    }

    /// The `session_meta` fields that say where a rollout's history came from.
    private struct SessionLineage: Sendable {
        let threadID: String
        let createdAt: Date?
        let isFork: Bool
        let historyBase: HistoryBase?
    }

    /// The running totals a rollout started from and where its own records begin.
    private struct InheritedUsage: Sendable {
        /// The `token_count` total.
        let total: CodexCumulativeTokenUsage
        /// The `token_usage_record` thread total; empty when no record came before.
        let record: CodexCumulativeTokenUsage
        /// Offset just past the records that came from the source thread.
        let ownRecordsOffset: UInt64
    }

    private struct InheritedUsageLookup: Sendable {
        let usage: InheritedUsage?
        /// Leading bytes of the rollout the result depends on.
        let headByteCount: UInt64
        /// False while the rollout is too new to tell; look again when it changes.
        let isFinal: Bool

        static let pending = InheritedUsageLookup(usage: nil, headByteCount: 0, isFinal: false)
    }

    private struct CachedInheritedUsage: Sendable {
        let headByteCount: UInt64
        let usage: InheritedUsage?
    }

    private enum LineageRecord {
        case tokenCount(CodexCumulativeTokenUsage, timestamp: Date?)
        case usageRecord(CodexCumulativeTokenUsage)
        case turnContext
        case settingsApplied(threadID: String?)
    }

    private let fileManager: FileManager
    private let directories: [URL]
    private let readChunkSize: Int
    private var cachedRollouts: [URL: CachedRollout] = [:]
    /// Rollouts that forks and reverts inherit from. Refreshed on every fetch.
    private var rolloutURLsByID: [String: URL] = [:]
    private var cachedInheritedUsage: [URL: CachedInheritedUsage] = [:]
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
        readChunkSize: Int = 64 * 1024,
        fileManager: FileManager = .default
    ) {
        precondition(readChunkSize > 0)
        self.directories = directories
        self.readChunkSize = readChunkSize
        self.fileManager = fileManager
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        let discovery = try rolloutFiles(modifiedAfter: since)
        let files = discovery.files
        rolloutURLsByID = discovery.urlsByRolloutID
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
                nextDiagnostics.bytesRead += result.reads.bytesRead
                nextDiagnostics.maximumBufferedBytes = max(
                    nextDiagnostics.maximumBufferedBytes,
                    result.reads.maximumBufferedBytes
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

        // A narrow consumer (the 30-day cost view) must not evict unchanged
        // sessions retained for the one-year effort view. Cap that preservation
        // at the same 13-month window as persisted usage so naturally aged-out
        // rollouts do not stay in memory for the actor's lifetime.
        let retentionCutoff = Calendar.current.date(
            byAdding: .month,
            value: -13,
            to: Date()
        ) ?? since
        cachedRollouts = cachedRollouts.filter { url, cached in
            currentURLs.contains(url)
                || (cached.fingerprint.modificationDate < since
                    && cached.fingerprint.modificationDate >= retentionCutoff)
        }
        cachedInheritedUsage = cachedInheritedUsage.filter { url, _ in
            cachedRollouts[url] != nil
        }
        diagnostics = nextDiagnostics
        return entries
    }

    /// Latest per-fetch diagnostics. Actor isolation keeps these consistent with the cache.
    func latestDiagnostics() -> CodexLogSourceDiagnostics {
        diagnostics
    }

    // MARK: - File discovery

    private func rolloutFiles(
        modifiedAfter cutoff: Date
    ) throws -> (files: [RolloutFile], urlsByRolloutID: [String: URL]) {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        var result: [RolloutFile] = []
        var urlsByRolloutID: [String: URL] = [:]
        var foundReadableDirectory = false

        for directory in directories {
            do {
                // Use a throwing read instead of `fileExists`, which can collapse
                // sandbox permission failures into a misleading `false` result.
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

            // A successful read must cover every existing Codex root. Otherwise
            // one granted CLI directory could hide inaccessible Xcode sessions
            // and turn incomplete data into a misleading zero-usage result.
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
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-"),
                      let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true else { continue }
                // A fork or revert can continue from a rollout older than the cutoff.
                urlsByRolloutID[Self.rolloutIdentifiers(for: url).rollout] = url
                guard let modificationDate = values.contentModificationDate,
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

            guard !traversalFailed else {
                throw UsageLogSourceError.unavailable
            }
        }

        guard foundReadableDirectory else {
            throw UsageLogSourceError.unavailable
        }
        return (result, urlsByRolloutID)
    }

    private nonisolated static func isMissingDirectoryError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        guard cocoaError.domain == NSCocoaErrorDomain else { return false }
        return cocoaError.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoaError.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }

    // MARK: - Parsing

    /// Scans complete JSONL records from the end of the file. Codex appends the
    /// cumulative token usage and current model near the tail, so unchanged history
    /// never needs to be loaded or decoded.
    private func parseRollout(_ file: RolloutFile) -> ParseResult {
        guard file.fingerprint.size > 0,
              let handle = try? FileHandle(forReadingFrom: file.url) else {
            return .empty
        }
        defer { try? handle.close() }

        var reads = ReadStats()
        let metadataProbe = probeSessionMetadata(
            handle: handle,
            fileSize: file.fingerprint.size,
            reads: &reads
        )
        let identifiers = Self.rolloutIdentifiers(for: file.url)
        // Forks and the newer rollouts of reverted threads start from another rollout's total.
        let inherited = metadataProbe.isFork || identifiers.thread != identifiers.rollout
            ? inheritedUsage(for: file, handle: handle, reads: &reads)
            : nil
        var latestModel: String?
        var latestEffortLevel: EffortLevel?
        var tokenScan = CodexUsageRecordScan()
        var latestTimestamp: Date?

        do {
            // Records before a fork's own were copied from its source and are not its usage.
            try scanRecordsBackward(
                handle: handle,
                from: UInt64(file.fingerprint.size),
                to: inherited?.ownRecordsOffset ?? 0,
                reads: &reads
            ) { line in
                inspect(
                    line: line,
                    latestModel: &latestModel,
                    latestEffortLevel: &latestEffortLevel,
                    tokenScan: &tokenScan,
                    latestTimestamp: &latestTimestamp
                )
                return hasCompleteResult(
                    model: latestModel,
                    tokenScan: tokenScan,
                    timestamp: latestTimestamp
                )
            }
        } catch {
            return ParseResult(entry: nil, reads: reads)
        }

        guard let total = tokenScan.sessionTotal(
            inheritedTokenCount: inherited?.total,
            inheritedRecord: inherited?.record
        ) else {
            return ParseResult(entry: nil, reads: reads)
        }

        // Codex: total = input + output; `input` includes cached, `output` includes reasoning.
        // Split into disjoint components so totals/cost don't double-count.
        let tokens = TokenCount(
            inputTokens: max(0, total.inputTokens - total.cachedInputTokens),
            outputTokens: max(0, total.outputTokens - total.reasoningOutputTokens),
            cacheCreationTokens: 0,
            cacheReadTokens: total.cachedInputTokens,
            reasoningTokens: total.reasoningOutputTokens
        )

        let entry = ProviderUsageEntry(
            provider: .codex,
            model: latestModel ?? "gpt-5-codex",
            pricingProviderKey: "openai",
            tokens: tokens,
            timestamp: latestTimestamp ?? file.fingerprint.modificationDate,
            // A reverted thread's rollouts share the thread ID. Each counts its own usage.
            dedupKey: "codex:\(identifiers.rollout)",
            sessionID: identifiers.thread,
            effortLevel: latestEffortLevel,
            isSubagentSession: metadataProbe.isSubagentSession
        )
        return ParseResult(entry: entry, reads: reads)
    }

    /// Visits complete JSONL records from `end` back to `start`, newest first, until
    /// `visit` returns true. `start` must be a record boundary.
    private func scanRecordsBackward(
        handle: FileHandle,
        from end: UInt64,
        to start: UInt64,
        reads: inout ReadStats,
        visit: (Data) -> Bool
    ) throws {
        var position = end
        var pendingLineFragments: [Data] = []
        var pendingLineByteCount = 0

        while position > start {
            let count = Int(min(UInt64(readChunkSize), position - start))
            position -= UInt64(count)
            try handle.seek(toOffset: position)

            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                return
            }
            reads.bytesRead += chunk.count
            reads.buffered(pendingLineByteCount + chunk.count)

            var lineEnd = chunk.endIndex
            while let newline = chunk[..<lineEnd].lastIndex(of: 0x0A) {
                let lineStart = chunk.index(after: newline)
                if lineStart < lineEnd || pendingLineByteCount > 0 {
                    let line: Data
                    if pendingLineByteCount == 0 {
                        line = chunk[lineStart..<lineEnd]
                    } else {
                        line = assembleLine(
                            prefix: chunk[lineStart..<lineEnd],
                            fragments: &pendingLineFragments,
                            fragmentByteCount: &pendingLineByteCount
                        )
                        reads.buffered(line.count)
                    }
                    if visit(line) {
                        return
                    }
                }
                lineEnd = newline
            }

            if lineEnd > chunk.startIndex {
                let fragment = Data(chunk[..<lineEnd])
                pendingLineByteCount += fragment.count
                pendingLineFragments.append(fragment)
                reads.buffered(pendingLineByteCount)
            }

            if position == start, pendingLineByteCount > 0 {
                let line = assembleLine(
                    prefix: Data(),
                    fragments: &pendingLineFragments,
                    fragmentByteCount: &pendingLineByteCount
                )
                reads.buffered(line.count)
                _ = visit(line)
            }
        }
    }

    /// Visits complete JSONL records from `start` to the end of the file, oldest first,
    /// until `visit` returns true. `visit` also gets the offset just past the record. A
    /// final record without its newline is still being written and is not visited.
    private func scanRecordsForward(
        handle: FileHandle,
        from start: UInt64,
        byteCount: UInt64,
        reads: inout ReadStats,
        visit: (Data, UInt64) -> Bool
    ) throws {
        try handle.seek(toOffset: start)
        var position = start
        var pendingLine = Data()

        while position < byteCount {
            let count = Int(min(UInt64(readChunkSize), byteCount - position))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                return
            }
            let chunkOffset = position
            position += UInt64(chunk.count)
            reads.bytesRead += chunk.count
            reads.buffered(pendingLine.count + chunk.count)

            var lineStart = chunk.startIndex
            while let newline = chunk[lineStart...].firstIndex(of: 0x0A) {
                let recordEnd = chunkOffset + UInt64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                if lineStart < newline || !pendingLine.isEmpty {
                    let line: Data
                    if pendingLine.isEmpty {
                        line = chunk[lineStart..<newline]
                    } else {
                        pendingLine.append(chunk[lineStart..<newline])
                        reads.buffered(pendingLine.count)
                        line = pendingLine
                        pendingLine = Data()
                    }
                    if visit(line, recordEnd) {
                        return
                    }
                }
                lineStart = chunk.index(after: newline)
            }
            pendingLine.append(chunk[lineStart...])
        }
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
        tokenScan: CodexUsageRecordScan,
        timestamp: Date?
    ) -> Bool {
        model != nil && tokenScan.isComplete && timestamp != nil
    }

    /// Inspects only records that could contain data we still need. The substring
    /// checks avoid decoding large prompt/tool-output records as JSON.
    private func inspect(
        line: Data,
        latestModel: inout String?,
        latestEffortLevel: inout EffortLevel?,
        tokenScan: inout CodexUsageRecordScan,
        latestTimestamp: inout Date?
    ) {
        let needsTotal = !tokenScan.isComplete
        let mayContainTurnContext = (latestModel == nil || tokenScan.needsTurnBoundary)
            && line.range(of: Self.turnContextMarker) != nil
        let mayContainUsage = (needsTotal || latestTimestamp == nil)
            && (line.range(of: Self.tokenCountMarker) != nil
                || line.range(of: Self.tokenUsageRecordMarker) != nil)
        guard mayContainTurnContext || mayContainUsage,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return }

        let payload = json["payload"] as? [String: Any]
        if mayContainTurnContext, type == "turn_context" {
            tokenScan.recordTurnContext()
            if latestModel == nil,
               let model = payload?["model"] as? String,
               !model.isEmpty {
                latestModel = model
                latestEffortLevel = Self.normalizedEffortLevel(payload?["effort"])
            }
            return
        }

        guard mayContainUsage else { return }
        switch type {
        case "token_usage_record":
            guard let threadUsage = payload?["thread_token_usage"] as? [String: Any] else { return }
            if needsTotal {
                tokenScan.recordUsageRecord(CodexCumulativeTokenUsage(threadUsage))
            }
        case "event_msg":
            guard payload?["type"] as? String == "token_count",
                  let info = payload?["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return }
            if needsTotal {
                tokenScan.recordTokenCount(CodexCumulativeTokenUsage(total))
            }
        default:
            return
        }

        if latestTimestamp == nil {
            latestTimestamp = date(from: json["timestamp"])
        }
    }

    private func date(from value: Any?) -> Date? {
        guard let timestamp = value as? String else { return nil }
        return isoFormatter.date(from: timestamp)
            ?? isoFormatterNoFraction.date(from: timestamp)
    }

    private nonisolated static func normalizedEffortLevel(_ value: Any?) -> EffortLevel? {
        guard let rawValue = value as? String else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : EffortLevel(rawValue: normalized)
    }

    private static let turnContextMarker = Data(#""turn_context""#.utf8)
    private static let tokenCountMarker = Data(#""token_count""#.utf8)
    private static let tokenUsageRecordMarker = Data(#""token_usage_record""#.utf8)
    private static let settingsAppliedMarker = Data(#""thread_settings_applied""#.utf8)
    private static let sessionMetaMarker = Data(#""session_meta""#.utf8)
    private static let forkedFromMarker = Data(#""forked_from_id":""#.utf8)
    private static let subagentThreadMarker = Data(#""thread_source":"subagent""#.utf8)
    private static let subagentSourceMarker = Data(#""source":{"subagent""#.utf8)
    private static let metadataProbeSize = 8 * 1_024

    /// `session_meta` is the first rollout record. It can contain megabytes of
    /// base instructions, but its identity and source fields occur near the
    /// beginning, so a fixed prefix is enough to identify spawned subagent
    /// sessions and forks.
    private func probeSessionMetadata(
        handle: FileHandle,
        fileSize: Int64,
        reads: inout ReadStats
    ) -> (isSubagentSession: Bool, isFork: Bool) {
        do {
            try handle.seek(toOffset: 0)
            let count = min(Self.metadataProbeSize, Int(fileSize))
            guard let prefix = try handle.read(upToCount: count) else {
                return (false, false)
            }
            reads.bytesRead += prefix.count
            reads.buffered(prefix.count)
            guard prefix.range(of: Self.sessionMetaMarker) != nil else {
                return (false, false)
            }
            let isSubagent = prefix.range(of: Self.subagentThreadMarker) != nil
                || prefix.range(of: Self.subagentSourceMarker) != nil
            // A copied fork can repeat its source's `session_meta` as a later record.
            let firstRecord = prefix.firstIndex(of: 0x0A).map { prefix[..<$0] } ?? prefix
            return (isSubagent, firstRecord.range(of: Self.forkedFromMarker) != nil)
        } catch {
            return (false, false)
        }
    }

    /// Rollout filenames end in the thread UUID. The new rollout that reverting a
    /// thread starts appends `_<rollout UUID>`. Using the filename avoids reading the
    /// potentially multi-megabyte `session_meta` record at the start of the file.
    private nonisolated static func rolloutIdentifiers(
        for url: URL
    ) -> (thread: String, rollout: String) {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let rollout = uuidSuffix(of: Substring(stem)) else {
            return (stem, stem)
        }
        let threadPart = stem.dropLast(36)
        guard threadPart.hasSuffix("_"),
              let thread = uuidSuffix(of: threadPart.dropLast()) else {
            return (rollout, rollout)
        }
        return (thread, rollout)
    }

    private nonisolated static func uuidSuffix(of text: Substring) -> String? {
        let candidate = String(text.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate.lowercased()
    }

    // MARK: - Inherited usage

    /// Codex writes a copied fork's source records and the fork's own settings record in
    /// the same append that creates the rollout. A `token_count` stamped later than this
    /// after `session_meta` is the fork's own, so reaching one first means Codex wrote the
    /// fork before it recorded where copied history ends (before late August 2026). Those
    /// forks are left as they are.
    private static let copiedHistoryWriteWindow: TimeInterval = 60
    private static let maximumReferenceDepth = 16

    /// The running totals a fork or a reverted thread's rollout started from. The records
    /// this depends on never change once written, so the result is cached per rollout.
    private func inheritedUsage(
        for file: RolloutFile,
        handle: FileHandle,
        reads: inout ReadStats
    ) -> InheritedUsage? {
        let byteCount = UInt64(file.fingerprint.size)
        if let cached = cachedInheritedUsage[file.url], cached.headByteCount <= byteCount {
            return cached.usage
        }
        let lookup = (try? lookUpInheritedUsage(
            handle: handle,
            byteCount: byteCount,
            reads: &reads
        )) ?? .pending
        if lookup.isFinal {
            cachedInheritedUsage[file.url] = CachedInheritedUsage(
                headByteCount: lookup.headByteCount,
                usage: lookup.usage
            )
        }
        return lookup.usage
    }

    private func lookUpInheritedUsage(
        handle: FileHandle,
        byteCount: UInt64,
        reads: inout ReadStats
    ) throws -> InheritedUsageLookup {
        guard let (lineage, metadataEnd) = try readSessionLineage(
            handle: handle,
            byteCount: byteCount,
            reads: &reads
        ) else {
            return .pending
        }

        if let historyBase = lineage.historyBase {
            // Referenced forks and reverted threads keep the inherited records in the
            // source rollout, so look up the totals there.
            guard let totals = inheritedTotals(at: historyBase, reads: &reads) else {
                return InheritedUsageLookup(usage: nil, headByteCount: metadataEnd, isFinal: false)
            }
            return InheritedUsageLookup(
                usage: InheritedUsage(
                    total: totals.tokenCount,
                    record: totals.record,
                    ownRecordsOffset: metadataEnd
                ),
                headByteCount: metadataEnd,
                isFinal: true
            )
        }
        guard lineage.isFork else {
            return InheritedUsageLookup(usage: nil, headByteCount: metadataEnd, isFinal: true)
        }

        // A copied fork repeats its source's records, then records its own settings with
        // its thread ID. Codex seeded the fork with the newest copied totals. A forked
        // subagent's copy leaves out usage records, so its records start empty.
        var copiedTotal = CodexCumulativeTokenUsage()
        var copiedRecord = CodexCumulativeTokenUsage()
        var lookup = InheritedUsageLookup.pending
        try scanRecordsForward(
            handle: handle,
            from: metadataEnd,
            byteCount: byteCount,
            reads: &reads
        ) { record, recordEnd in
            switch lineageRecord(in: record) {
            case let .tokenCount(total, timestamp):
                if let createdAt = lineage.createdAt,
                   let timestamp,
                   timestamp.timeIntervalSince(createdAt) > Self.copiedHistoryWriteWindow {
                    lookup = InheritedUsageLookup(usage: nil, headByteCount: recordEnd, isFinal: true)
                    return true
                }
                copiedTotal = total
            case let .usageRecord(threadTotal):
                copiedRecord = threadTotal
            case let .settingsApplied(threadID) where threadID == lineage.threadID:
                lookup = InheritedUsageLookup(
                    usage: InheritedUsage(
                        total: copiedTotal,
                        record: copiedRecord,
                        ownRecordsOffset: recordEnd
                    ),
                    headByteCount: recordEnd,
                    isFinal: true
                )
                return true
            case .settingsApplied, .turnContext, nil:
                break
            }
            return false
        }
        return lookup
    }

    /// Codex seeds a Referenced fork or a reverted thread from the newest `token_count`
    /// and usage record before the source point, continuing into the source's own source
    /// when its prefix has none. Returns nil when a rollout on the way is not readable
    /// here, such as a compressed one; its usage is not counted here either.
    private func inheritedTotals(
        at historyBase: HistoryBase,
        reads: inout ReadStats
    ) -> (tokenCount: CodexCumulativeTokenUsage, record: CodexCumulativeTokenUsage)? {
        var historyBase = historyBase
        var inheritedRecord: CodexCumulativeTokenUsage?
        for _ in 0..<Self.maximumReferenceDepth {
            guard let url = rolloutURLsByID[historyBase.rolloutID],
                  let handle = try? FileHandle(forReadingFrom: url) else {
                return nil
            }
            defer { try? handle.close() }

            do {
                let byteCount = try handle.seekToEnd()
                var scan = CodexUsageRecordScan()
                try scanRecordsBackward(
                    handle: handle,
                    from: min(historyBase.endByteOffset, byteCount),
                    to: 0,
                    reads: &reads
                ) { record in
                    switch lineageRecord(in: record) {
                    case let .tokenCount(total, _):
                        scan.recordTokenCount(total)
                    case let .usageRecord(threadTotal):
                        scan.recordUsageRecord(threadTotal)
                    case .turnContext:
                        scan.recordTurnContext()
                    case .settingsApplied, nil:
                        break
                    }
                    return scan.isComplete
                }
                inheritedRecord = inheritedRecord ?? scan.recordTotal
                if let tokenCount = scan.tokenCountTotal {
                    return (tokenCount, inheritedRecord ?? CodexCumulativeTokenUsage())
                }
                guard let (lineage, _) = try readSessionLineage(
                    handle: handle,
                    byteCount: byteCount,
                    reads: &reads
                ) else {
                    return nil
                }
                guard let next = lineage.historyBase else {
                    return (CodexCumulativeTokenUsage(), inheritedRecord ?? CodexCumulativeTokenUsage())
                }
                historyBase = next
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Reads `session_meta`, the first record, in full: `history_base` follows the base
    /// instructions. Returns nil while it is still being written or if it is not one.
    private func readSessionLineage(
        handle: FileHandle,
        byteCount: UInt64,
        reads: inout ReadStats
    ) throws -> (SessionLineage, recordEnd: UInt64)? {
        var result: (SessionLineage, recordEnd: UInt64)?
        try scanRecordsForward(
            handle: handle,
            from: 0,
            byteCount: byteCount,
            reads: &reads
        ) { record, recordEnd in
            result = sessionLineage(in: record).map { ($0, recordEnd) }
            return true
        }
        return result
    }

    private func sessionLineage(in record: Data) -> SessionLineage? {
        guard let json = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
              json["type"] as? String == "session_meta",
              let payload = json["payload"] as? [String: Any],
              let threadID = payload["id"] as? String else { return nil }

        var historyBase: HistoryBase?
        if let base = payload["history_base"] as? [String: Any],
           let rolloutID = base["thread_id"] as? String,
           let endByteOffset = base["end_byte_offset"] as? Int,
           endByteOffset >= 0 {
            historyBase = HistoryBase(
                rolloutID: rolloutID.lowercased(),
                endByteOffset: UInt64(endByteOffset)
            )
        }
        return SessionLineage(
            threadID: threadID.lowercased(),
            createdAt: date(from: json["timestamp"]),
            isFork: payload["forked_from_id"] is String,
            historyBase: historyBase
        )
    }

    private func lineageRecord(in record: Data) -> LineageRecord? {
        guard record.range(of: Self.tokenCountMarker) != nil
                || record.range(of: Self.tokenUsageRecordMarker) != nil
                || record.range(of: Self.turnContextMarker) != nil
                || record.range(of: Self.settingsAppliedMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else { return nil }

        switch json["type"] as? String {
        case "token_usage_record":
            guard let threadUsage = payload["thread_token_usage"] as? [String: Any] else { return nil }
            return .usageRecord(CodexCumulativeTokenUsage(threadUsage))
        case "turn_context":
            return .turnContext
        case "event_msg":
            break
        default:
            return nil
        }

        switch payload["type"] as? String {
        case "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return nil }
            return .tokenCount(
                CodexCumulativeTokenUsage(total),
                timestamp: date(from: json["timestamp"])
            )
        case "thread_settings_applied":
            // Copied settings records keep their source thread's ID; older ones have none.
            return .settingsApplied(threadID: (payload["thread_id"] as? String)?.lowercased())
        default:
            return nil
        }
    }
}
#endif
