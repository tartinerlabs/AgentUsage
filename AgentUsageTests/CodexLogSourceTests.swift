//
//  CodexLogSourceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@MainActor
@Suite("Codex Log Source")
struct CodexLogSourceTests {
    @Test func readsLatestModelAndCumulativeTokenCountFromTail() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = "019f7bb3-c080-7ed0-bb08-234e920ae647"
        let file = directory.appendingPathComponent("rollout-2026-07-20T00-00-00-\(sessionID).jsonl")
        let oldTimestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let latestTimestamp = oldTimestamp.addingTimeInterval(60)
        let content = [
            Self.turnContext(model: "gpt-old", effort: "xhigh"),
            Self.tokenCount(timestamp: oldTimestamp, input: 20, cached: 5, output: 8, reasoning: 2),
            "not-json",
            Self.tokenCount(timestamp: latestTimestamp, input: 100, cached: 30, output: 50, reasoning: 10),
            Self.turnContext(model: "gpt-latest", effort: "  MeDiuM  "),
        ].joined(separator: "\n") + "\n"
        try Self.write(content, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 73)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.model == "gpt-latest")
        #expect(entry.tokens.inputTokens == 70)
        #expect(entry.tokens.cacheReadTokens == 30)
        #expect(entry.tokens.outputTokens == 40)
        #expect(entry.tokens.reasoningTokens == 10)
        #expect(entry.timestamp == latestTimestamp)
        #expect(entry.dedupKey == "codex:\(sessionID)")
        #expect(entry.sessionID == sessionID)
        #expect(entry.effortLevel?.rawValue == "medium")
    }

    @Test func skipsMalformedCandidatesAndFallsBackWithoutModelOrSessionUUID() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-custom.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let content = [
            Self.tokenCount(timestamp: timestamp, input: 15, cached: 3, output: 7, reasoning: 2),
            #"{"type":"event_msg","payload":{"type":"token_count""#,
            #"{"type":"turn_context","payload":{"model":""}}"#,
        ].joined(separator: "\n")
        try Self.write(content, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 31)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entry.model == "gpt-5-codex")
        #expect(entry.tokens.totalTokens == 22)
        #expect(entry.timestamp == timestamp)
        #expect(entry.dedupKey == "codex:rollout-custom")
        #expect(entry.sessionID == "rollout-custom")
        #expect(entry.effortLevel == nil)
    }

    @Test func latestTurnContextWithoutEffortDoesNotReuseOlderEffort() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-effort.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let content = [
            Self.turnContext(model: "gpt-old", effort: "xhigh"),
            Self.tokenCount(timestamp: timestamp, input: 15),
            Self.turnContext(model: "gpt-latest"),
        ].joined(separator: "\n")
        try Self.write(content, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 37)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entry.model == "gpt-latest")
        #expect(entry.effortLevel == nil)
    }

    @Test func preservesUnknownNormalizedEffortValue() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-future-effort.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let content = [
            Self.tokenCount(timestamp: timestamp, input: 15),
            Self.turnContext(model: "gpt-future", effort: "  Adaptive-Plus "),
        ].joined(separator: "\n")
        try Self.write(content, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 41)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(entry.effortLevel?.rawValue == "adaptive-plus")
    }

    @Test func marksSpawnedSubagentSessionsForEffortExclusion() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-subagent.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let content = [
            #"{"timestamp":"2026-07-20T00:00:00Z","type":"session_meta","payload":{"id":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}},"thread_source":"subagent"}}"#,
            Self.turnContext(model: "gpt-subagent", effort: "ultra"),
            Self.tokenCount(timestamp: timestamp, input: 15),
        ].joined(separator: "\n")
        try Self.write(content, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 41)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)
        let service = TokenUsageService(extraSources: [source])
        let samples = await service.fetchExtraProviderEffortSamples(since: .distantPast)

        #expect(entry.isSubagentSession)
        #expect(samples.count == 1)
        #expect(samples.first?.isSubagentSession == true)
        #expect(EffortUsageAggregator.summaries(from: samples).isEmpty)
    }

    /// `codex exec` records through the same rollout writer as interactive Codex,
    /// into `sessions/<yyyy>/<mm>/<dd>/`. Only `session_meta` tells them apart.
    @Test func readsHeadlessExecRolloutLikeInteractiveSessions() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dayDirectory = directory.appendingPathComponent("2026/09/20", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        let sessionID = "019f8c2a-4d51-7a30-9e6b-5f0c1d2e3a4b"
        let file = dayDirectory.appendingPathComponent("rollout-2026-09-20T10-00-00-\(sessionID).jsonl")
        let firstResponse = Self.codexTokenUsage(input: 12_000, cached: 8_000, output: 900, reasoning: 300)
        let secondResponse = Self.codexTokenUsage(input: 15_000, cached: 12_000, output: 400, reasoning: 100)
        let cumulative = Self.codexTokenUsage(input: 27_000, cached: 20_000, output: 1_300, reasoning: 400)
        let lines: [String] = [
            Self.execSessionMeta(sessionID: sessionID, timestamp: "2026-09-20T10:00:00.100Z"),
            Self.pagedTurnContext(
                timestamp: "2026-09-20T10:00:00.200Z", ordinal: 1, model: "gpt-5.5-codex", effort: "high"
            ),
            #"{"timestamp":"2026-09-20T10:00:00.210Z","ordinal":2,"type":"response_item","#
                + #""payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Summarize"}]}}"#,
            // A rate-limit update streamed before the response completes has no `info`.
            #"{"timestamp":"2026-09-20T10:00:01.000Z","ordinal":3,"type":"event_msg","#
                + #""payload":{"type":"token_count","info":null,"rate_limits":\#(Self.codexRateLimits)}}"#,
            Self.tokenUsageRecord(
                timestamp: "2026-09-20T10:00:04.500Z", ordinal: 4, sessionID: sessionID,
                responseID: "resp-1", usage: firstResponse, threadUsage: firstResponse
            ),
            Self.pagedTokenCount(
                timestamp: "2026-09-20T10:00:04.510Z", ordinal: 5, total: firstResponse, last: firstResponse
            ),
            Self.tokenUsageRecord(
                timestamp: "2026-09-20T10:00:09.800Z", ordinal: 6, sessionID: sessionID,
                responseID: "resp-2", usage: secondResponse, threadUsage: cumulative
            ),
            Self.pagedTokenCount(
                timestamp: "2026-09-20T10:00:09.810Z", ordinal: 7, total: cumulative, last: secondResponse
            ),
            #"{"timestamp":"2026-09-20T10:00:09.900Z","ordinal":8,"type":"event_msg","#
                + #""payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Done"}}"#,
        ]
        try Self.write(lines.joined(separator: "\n") + "\n", to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 97)
        let entries = try await source.fetchEntries(since: .distantPast)
        let entry = try #require(entries.first)
        let lastTokenCount = try Self.codexDate("2026-09-20T10:00:09.810Z")

        #expect(entries.count == 1)
        #expect(entry.provider == .codex)
        #expect(entry.model == "gpt-5.5-codex")
        #expect(entry.effortLevel?.rawValue == "high")
        #expect(!entry.isSubagentSession)
        #expect(entry.tokens.inputTokens == 7_000)
        #expect(entry.tokens.cacheReadTokens == 20_000)
        #expect(entry.tokens.outputTokens == 900)
        #expect(entry.tokens.reasoningTokens == 400)
        #expect(entry.timestamp == lastTokenCount)
        #expect(entry.dedupKey == "codex:\(sessionID)")
    }

    @Test @MainActor func successfulEmptyThirtyDayReadRemainsAvailableAlongsideOlderEffort() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingDirectory = directory.appendingPathComponent("optional-missing-root")
        let file = directory.appendingPathComponent("rollout-older-effort.jsonl")
        let now = Date()
        let olderTimestamp = now.addingTimeInterval(-60 * 24 * 60 * 60)
        let content = [
            Self.turnContext(model: "gpt-5.6-codex", effort: "high"),
            Self.tokenCount(timestamp: olderTimestamp, input: 15),
        ].joined(separator: "\n")
        try Self.write(content, to: file)
        try Self.setModificationDate(olderTimestamp, for: file)

        let service = TokenUsageService(
            extraSources: [CodexLogSource(directories: [directory, missingDirectory])]
        )
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            defaults: TestUserDefaults().defaults,
            now: { now }
        )

        let details = await coordinator.providerDetails(using: nil)
        let detail = try #require(details[.codex])
        let effort = try #require(detail.effortSummary(for: .last90Days))

        #expect(detail.hasTokenUsage)
        #expect(detail.last30Days.tokens.totalTokens == 0)
        #expect(effort.sessionCount(for: .high) == 1)
    }

    @Test func partiallyReadableSourceDoesNotSynthesizeZeroTokenDetail() async throws {
        let readableDirectory = try Self.temporaryDirectory()
        let inaccessibleDirectory = try Self.temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: readableDirectory)
            try? FileManager.default.removeItem(at: inaccessibleDirectory)
        }
        let fileManager = SandboxDeniedFileManager(
            deniedDirectory: inaccessibleDirectory
        )
        let service = TokenUsageService(
            extraSources: [
                CodexLogSource(
                    directories: [readableDirectory, inaccessibleDirectory],
                    fileManager: fileManager
                ),
            ]
        )

        let details = await service.fetchExtraProviderDetails(since: .distantPast)

        #expect(details[.codex] == nil)
    }

    @Test func unavailableSourceDoesNotSynthesizeZeroTokenDetail() async {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexLogSourceTests-missing-\(UUID().uuidString)")
        let service = TokenUsageService(
            extraSources: [CodexLogSource(directories: [missingDirectory])]
        )

        let details = await service.fetchExtraProviderDetails(since: .distantPast)

        #expect(details[.codex] == nil)
    }

    @Test func usesModificationDateWhenTokenTimestampIsMissing() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-no-timestamp.jsonl")
        let modificationDate = Date(timeIntervalSince1970: 1_752_970_000)
        let content = [
            Self.turnContext(model: "gpt-5.6-codex"),
            Self.tokenCountWithoutTimestamp(input: 12),
        ].joined(separator: "\n")
        try Self.write(content, to: file)
        try Self.setModificationDate(modificationDate, for: file)
        let actualModificationDate = try Self.modificationDate(of: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 29)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entry.timestamp == actualModificationDate)
        #expect(entry.tokens.inputTokens == 12)
    }

    @Test func cachesUnchangedFilesIncludingEmptyResults() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let populated = directory.appendingPathComponent("rollout-populated.jsonl")
        let empty = directory.appendingPathComponent("rollout-empty.jsonl")
        try Self.write(
            [
                Self.turnContext(model: "gpt-cached"),
                Self.tokenCount(timestamp: timestamp, input: 10),
            ].joined(separator: "\n"),
            to: populated
        )
        try Data().write(to: empty)

        let source = CodexLogSource(directories: [directory], readChunkSize: 64)
        let firstEntries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let firstDiagnostics = await source.latestDiagnostics()
        let secondEntries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let secondDiagnostics = await source.latestDiagnostics()

        #expect(firstEntries.count == 1)
        #expect(secondEntries.count == 1)
        #expect(firstDiagnostics.parsedFileCount == 2)
        #expect(firstDiagnostics.cacheHitCount == 0)
        #expect(secondDiagnostics.parsedFileCount == 0)
        #expect(secondDiagnostics.cacheHitCount == 2)
        #expect(secondDiagnostics.bytesRead == 0)
    }

    @Test func narrowQueryKeepsOlderEntriesCachedForEffortHistory() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let recent = directory.appendingPathComponent("rollout-recent.jsonl")
        let older = directory.appendingPathComponent("rollout-older.jsonl")
        let sixtyDays: TimeInterval = 60 * 24 * 60 * 60

        try Self.write(
            [
                Self.turnContext(model: "gpt-recent", effort: "xhigh"),
                Self.tokenCount(timestamp: now, input: 10),
            ].joined(separator: "\n"),
            to: recent
        )
        try Self.write(
            [
                Self.turnContext(model: "gpt-older", effort: "high"),
                Self.tokenCount(timestamp: now.addingTimeInterval(-sixtyDays), input: 20),
            ].joined(separator: "\n"),
            to: older
        )
        try Self.setModificationDate(now, for: recent)
        try Self.setModificationDate(now.addingTimeInterval(-sixtyDays), for: older)

        let source = CodexLogSource(directories: [directory])
        let broadCutoff = now.addingTimeInterval(-365 * 24 * 60 * 60)
        _ = try await source.fetchEntries(since: broadCutoff)
        _ = try await source.fetchEntries(since: now.addingTimeInterval(-30 * 24 * 60 * 60))
        let entries = try await source.fetchEntries(since: broadCutoff)
        let diagnostics = await source.latestDiagnostics()

        #expect(entries.count == 2)
        #expect(diagnostics.parsedFileCount == 0)
        #expect(diagnostics.cacheHitCount == 2)
    }

    @Test func narrowQueryPrunesEntriesBeyondRetainedHistory() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let file = directory.appendingPathComponent("rollout-beyond-retention.jsonl")
        let oldDate = Calendar.current.date(byAdding: .month, value: -14, to: now)
            ?? now.addingTimeInterval(-400 * 24 * 60 * 60)
        try Self.write(
            [
                Self.turnContext(model: "gpt-old", effort: "high"),
                Self.tokenCount(timestamp: oldDate, input: 10),
            ].joined(separator: "\n"),
            to: file
        )
        try Self.setModificationDate(oldDate, for: file)

        let source = CodexLogSource(directories: [directory])
        _ = try await source.fetchEntries(since: .distantPast)
        _ = try await source.fetchEntries(since: now.addingTimeInterval(-30 * 24 * 60 * 60))
        _ = try await source.fetchEntries(since: .distantPast)
        let diagnostics = await source.latestDiagnostics()

        #expect(diagnostics.parsedFileCount == 1)
        #expect(diagnostics.cacheHitCount == 0)
    }

    @Test func invalidatesCacheForAppendTruncationAndModificationDateChanges() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-changing.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let initial = [
            Self.turnContext(model: "gpt-initial"),
            Self.tokenCount(timestamp: timestamp, input: 10),
        ].joined(separator: "\n") + "\n"
        try Self.write(initial, to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 64)
        _ = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))

        let appended = [
            Self.turnContext(model: "gpt-appended"),
            Self.tokenCount(timestamp: timestamp.addingTimeInterval(60), input: 25),
        ].joined(separator: "\n") + "\n"
        try Self.append(appended, to: file)
        var entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        var diagnostics = await source.latestDiagnostics()
        #expect(entries.first?.model == "gpt-appended")
        #expect(entries.first?.tokens.inputTokens == 25)
        #expect(diagnostics.parsedFileCount == 1)

        let truncated = [
            Self.turnContext(model: "gpt-truncated"),
            Self.tokenCount(timestamp: timestamp.addingTimeInterval(120), input: 7),
        ].joined(separator: "\n")
        try Self.write(truncated, to: file)
        entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        diagnostics = await source.latestDiagnostics()
        #expect(entries.first?.model == "gpt-truncated")
        #expect(entries.first?.tokens.inputTokens == 7)
        #expect(diagnostics.parsedFileCount == 1)

        let previousModificationDate = try Self.modificationDate(of: file)
        try Self.setModificationDate(previousModificationDate.addingTimeInterval(60), for: file)
        entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        diagnostics = await source.latestDiagnostics()
        #expect(entries.first?.tokens.inputTokens == 7)
        #expect(diagnostics.parsedFileCount == 1)
        #expect(diagnostics.cacheHitCount == 0)
    }

    @Test func prunesDeletedFilesFromCache() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-deleted.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let content = [
            Self.turnContext(model: "gpt-delete"),
            Self.tokenCount(timestamp: timestamp, input: 10),
        ].joined(separator: "\n")
        try Self.write(content, to: file)
        let originalModificationDate = try Self.modificationDate(of: file)

        let source = CodexLogSource(directories: [directory])
        _ = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        try FileManager.default.removeItem(at: file)
        _ = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))

        try Self.write(content, to: file)
        try Self.setModificationDate(originalModificationDate, for: file)
        _ = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let diagnostics = await source.latestDiagnostics()

        #expect(diagnostics.parsedFileCount == 1)
        #expect(diagnostics.cacheHitCount == 0)
    }

    @Test func prunesFilesThatAgeOutsideTheCutoff() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-expired.jsonl")
        let now = Date()
        let timestamp = now.addingTimeInterval(-60)
        let content = [
            Self.turnContext(model: "gpt-cutoff"),
            Self.tokenCount(timestamp: timestamp, input: 10),
        ].joined(separator: "\n")
        try Self.write(content, to: file)
        try Self.setModificationDate(now.addingTimeInterval(-60), for: file)
        let eligibleModificationDate = try Self.modificationDate(of: file)
        let cutoff = now.addingTimeInterval(-3_600)

        let source = CodexLogSource(directories: [directory])
        _ = try await source.fetchEntries(since: cutoff)
        try Self.setModificationDate(now.addingTimeInterval(-7_200), for: file)
        _ = try await source.fetchEntries(since: cutoff)

        try Self.setModificationDate(eligibleModificationDate, for: file)
        _ = try await source.fetchEntries(since: cutoff)
        let diagnostics = await source.latestDiagnostics()

        #expect(diagnostics.parsedFileCount == 1)
        #expect(diagnostics.cacheHitCount == 0)
    }

    @Test func readsOnlyBoundedTailOfLargeRollout() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-large.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        var data = Data(repeating: 0x78, count: 8 * 1024 * 1024)
        data.append(0x0A)
        data.append(Data(Self.turnContext(model: "gpt-tail").utf8))
        data.append(0x0A)
        data.append(Data(Self.tokenCount(timestamp: timestamp, input: 40).utf8))
        data.append(0x0A)
        try data.write(to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 4 * 1024)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let diagnostics = await source.latestDiagnostics()

        #expect(entries.first?.model == "gpt-tail")
        #expect(entries.first?.tokens.inputTokens == 40)
        // One fixed 8 KiB prefix probes `session_meta`; the existing reverse
        // parser still needs at most one 4 KiB tail chunk for this fixture.
        #expect(diagnostics.bytesRead <= 12 * 1024)
        #expect(diagnostics.maximumBufferedBytes <= 8 * 1024)
        #expect(diagnostics.bytesRead < data.count / 500)
    }

    @Test func buffersAtMostOneLargeLineAcrossChunkBoundaries() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-large-line.jsonl")
        let timestamp = Date(timeIntervalSince1970: 1_752_969_600)
        let largeLineSize = 512 * 1024
        let content = Self.turnContext(model: "gpt-before-large-line")
            + "\n"
            + String(repeating: "x", count: largeLineSize)
            + "\n"
            + Self.tokenCount(timestamp: timestamp, input: 18)
            + "\n"
        try Self.write(content, to: file)

        let chunkSize = 1_024
        let source = CodexLogSource(directories: [directory], readChunkSize: chunkSize)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let diagnostics = await source.latestDiagnostics()

        #expect(entries.first?.model == "gpt-before-large-line")
        #expect(entries.first?.tokens.inputTokens == 18)
        #expect(diagnostics.maximumBufferedBytes <= largeLineSize + (2 * chunkSize))
    }

    // MARK: - Forks and reverts

    @Test func copiedForkCountsOnlyUsageAfterItsCopiedHistory() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a001"
        let forkID = "019f8a10-0000-7000-8000-00000000f001"
        let parentFile = directory.appendingPathComponent("rollout-2026-09-20T10-00-00-\(parentID).jsonl")
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T10-10-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let firstTurn = Usage(input: 1_000, cached: 200, output: 300, reasoning: 100)
        let secondTurn = Usage(input: 2_000, cached: 1_000, output: 400, reasoning: 150)
        let inherited = firstTurn + secondTurn
        let parentAfterFork = Usage(input: 900, cached: 600, output: 90, reasoning: 30)
        let parentTotal = inherited + parentAfterFork
        let forkTurn = Usage(input: 4_000, cached: 3_000, output: 500, reasoning: 200)

        try Self.write(Self.rollout([
            Self.sessionMeta(id: parentID, timestamp: forkedAt - 600),
            Self.settingsApplied(threadID: parentID, timestamp: forkedAt - 600),
            Self.turnContext(model: "gpt-5.4"),
            Self.codexTokenCount(total: firstTurn, last: firstTurn, timestamp: forkedAt - 540),
            Self.codexTokenCount(total: inherited, last: secondTurn, timestamp: forkedAt - 480),
            Self.turnContext(model: "gpt-5.4"),
            Self.codexTokenCount(total: parentTotal, last: parentAfterFork, timestamp: forkedAt + 60),
        ]), to: parentFile)
        // `/fork` copies the parent's records into the fork's rollout, stamped when the
        // fork is created, then records the fork's own settings.
        try Self.write(Self.rollout([
            Self.sessionMeta(id: forkID, timestamp: forkedAt, forkedFromID: parentID),
            Self.sessionMeta(id: parentID, timestamp: forkedAt),
            Self.settingsApplied(threadID: parentID, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.4"),
            Self.codexTokenCount(total: firstTurn, last: firstTurn, timestamp: forkedAt),
            Self.functionCallOutput(byteCount: 256 * 1_024, timestamp: forkedAt),
            Self.codexTokenCount(total: inherited, last: secondTurn, timestamp: forkedAt),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory])
        let beforeForkTurn = try await source.fetchEntries(since: .distantPast)

        // A fork without usage of its own yet contributes nothing.
        #expect(beforeForkTurn.map(\.dedupKey) == ["codex:\(parentID)"])

        try Self.append(Self.rollout([
            Self.turnContext(model: "gpt-5.5", effort: "high"),
            Self.codexTokenCount(
                total: inherited + forkTurn,
                last: forkTurn,
                timestamp: forkedAt + 120
            ),
        ]), to: forkFile)
        let entries = try await source.fetchEntries(since: .distantPast)
        let diagnostics = await source.latestDiagnostics()
        let parent = try #require(entries.first { $0.dedupKey == "codex:\(parentID)" })
        let fork = try #require(entries.first { $0.dedupKey == "codex:\(forkID)" })

        #expect(parent.tokens.totalTokens == parentTotal.total)
        #expect(fork.model == "gpt-5.5")
        #expect(fork.effortLevel?.rawValue == "high")
        #expect(fork.sessionID == forkID)
        #expect(fork.timestamp == forkedAt + 120)
        #expect(fork.tokens.inputTokens == 1_000)
        #expect(fork.tokens.cacheReadTokens == 3_000)
        #expect(fork.tokens.outputTokens == 300)
        #expect(fork.tokens.reasoningTokens == 200)
        // The copied history is looked up once, not read again as the fork grows.
        #expect(diagnostics.parsedFileCount == 1)
        #expect(diagnostics.bytesRead < 16 * 1_024)
    }

    @Test func copiedForkOfOverflowedParentCountsOnlyItsOwnUsage() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a002"
        let forkID = "019f8a10-0000-7000-8000-00000000f002"
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T11-00-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_003_600)
        let beforeOverflow = Usage(input: 250_000, cached: 200_000, output: 20_000, reasoning: 8_000)
        // Codex replaces the total with an empty one when a request overflows the window.
        let reset = Usage.contextWindowReset(272_000)
        let forkTurn = Usage(input: 30_000, cached: 10_000, output: 2_000, reasoning: 500)

        try Self.write(Self.rollout([
            Self.sessionMeta(id: forkID, timestamp: forkedAt, forkedFromID: parentID),
            Self.turnContext(model: "gpt-5.4"),
            Self.codexTokenCount(total: beforeOverflow, last: beforeOverflow, timestamp: forkedAt),
            Self.codexTokenCount(
                total: reset,
                last: Usage(total: reset.total - beforeOverflow.total),
                timestamp: forkedAt
            ),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(total: reset + forkTurn, last: forkTurn, timestamp: forkedAt + 90),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 97)
        let fork = try #require(try await source.fetchEntries(since: .distantPast).first)

        // The parent's pre-overflow usage belongs to the parent's rollout.
        #expect(fork.tokens.inputTokens == 20_000)
        #expect(fork.tokens.cacheReadTokens == 10_000)
        #expect(fork.tokens.outputTokens == 1_500)
        #expect(fork.tokens.reasoningTokens == 500)
    }

    @Test func forkThatOverflowsItsOwnWindowKeepsItsPostResetTotal() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a003"
        let forkID = "019f8a10-0000-7000-8000-00000000f003"
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T12-00-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_007_200)
        let inherited = Usage(input: 9_000, cached: 4_000, output: 800, reasoning: 300)
        let forkTurn = Usage(input: 200_000, cached: 150_000, output: 5_000, reasoning: 1_000)
        let reset = Usage.contextWindowReset(272_000)
        // Every counter exceeds the inherited total, so only the reset tells them apart.
        let afterReset = Usage(input: 12_000, cached: 5_000, output: 900, reasoning: 400)

        try Self.write(Self.rollout([
            Self.sessionMeta(id: forkID, timestamp: forkedAt, forkedFromID: parentID),
            Self.codexTokenCount(total: inherited, last: inherited, timestamp: forkedAt),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(total: inherited + forkTurn, last: forkTurn, timestamp: forkedAt + 60),
            Self.codexTokenCount(
                total: reset,
                last: Usage(total: reset.total - (inherited + forkTurn).total),
                timestamp: forkedAt + 120
            ),
            Self.codexTokenCount(total: reset + afterReset, last: afterReset, timestamp: forkedAt + 180),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory])
        let fork = try #require(try await source.fetchEntries(since: .distantPast).first)

        // The reset dropped the inherited total, so nothing is subtracted from what follows it.
        #expect(fork.tokens.inputTokens == 7_000)
        #expect(fork.tokens.cacheReadTokens == 5_000)
        #expect(fork.tokens.outputTokens == 500)
        #expect(fork.tokens.reasoningTokens == 400)
    }

    @Test func referencedForkSubtractsParentTotalAtForkPoint() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a004"
        let forkID = "019f8a10-0000-7000-8000-00000000f004"
        let parentFile = directory.appendingPathComponent("rollout-2026-08-10T09-00-00-\(parentID).jsonl")
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T13-00-00-\(forkID).jsonl")
        let now = Date()
        let forkedAt = now.addingTimeInterval(-3_600)
        let firstTurn = Usage(input: 5_000, cached: 1_000, output: 600, reasoning: 200)
        let secondTurn = Usage(input: 7_000, cached: 5_000, output: 900, reasoning: 400)
        let inherited = firstTurn + secondTurn
        let parentAfterFork = Usage(input: 3_000, cached: 2_000, output: 100, reasoning: 50)
        let forkTurn = Usage(input: 8_000, cached: 6_000, output: 1_200, reasoning: 700)

        let parentPrefix = [
            Self.sessionMeta(id: parentID, timestamp: forkedAt - 900, paginated: true),
            Self.settingsApplied(threadID: parentID, timestamp: forkedAt - 900, ordinal: 1),
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(total: firstTurn, last: firstTurn, timestamp: forkedAt - 840, ordinal: 3),
            Self.codexTokenCount(total: inherited, last: secondTurn, timestamp: forkedAt - 780, ordinal: 4),
        ]
        try Self.write(Self.rollout(parentPrefix + [
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(
                total: inherited + parentAfterFork,
                last: parentAfterFork,
                timestamp: forkedAt + 300,
                ordinal: 6
            ),
        ]), to: parentFile)
        // The parent is older than the query window; the fork still resolves against it.
        try Self.setModificationDate(now.addingTimeInterval(-40 * 24 * 60 * 60), for: parentFile)
        // A paginated fork records where it left the parent's rollout instead of copying it.
        try Self.write(Self.rollout([
            Self.sessionMeta(
                id: forkID,
                timestamp: forkedAt,
                forkedFromID: parentID,
                paginated: true,
                historyBase: HistoryBase(
                    rolloutID: parentID,
                    endOrdinalExclusive: parentPrefix.count,
                    endByteOffset: Data(Self.rollout(parentPrefix).utf8).count
                )
            ),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt, ordinal: 1),
            Self.turnContext(model: "gpt-5.5", effort: "xhigh"),
            Self.codexTokenCount(total: inherited + forkTurn, last: forkTurn, timestamp: now, ordinal: 3),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 89)
        let entries = try await source.fetchEntries(since: now.addingTimeInterval(-30 * 24 * 60 * 60))
        let fork = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(fork.dedupKey == "codex:\(forkID)")
        #expect(fork.effortLevel?.rawValue == "xhigh")
        #expect(fork.tokens.inputTokens == 2_000)
        #expect(fork.tokens.cacheReadTokens == 6_000)
        #expect(fork.tokens.outputTokens == 500)
        #expect(fork.tokens.reasoningTokens == 700)
    }

    @Test func revertCopyCountsOnlyUsageAfterTheRevert() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let threadID = "019f8a10-0000-7000-8000-00000000b005"
        let revertRolloutID = "019f8a10-0000-7000-8000-00000000c005"
        let originalFile = directory.appendingPathComponent("rollout-2026-09-21T09-00-00-\(threadID).jsonl")
        // `thread/revert` keeps the thread ID and starts a new rollout next to the original.
        let revertFile = directory.appendingPathComponent(
            "rollout-2026-09-21T09-30-00-\(threadID)_\(revertRolloutID).jsonl"
        )
        let startedAt = Date(timeIntervalSince1970: 1_790_060_000)
        let keptTurn = Usage(input: 6_000, cached: 2_000, output: 700, reasoning: 250)
        let revertedTurn = Usage(input: 9_000, cached: 6_000, output: 1_100, reasoning: 500)
        let turnAfterRevert = Usage(input: 3_000, cached: 2_500, output: 400, reasoning: 120)

        let keptPrefix = [
            Self.sessionMeta(id: threadID, timestamp: startedAt, paginated: true),
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(total: keptTurn, last: keptTurn, timestamp: startedAt + 60, ordinal: 2),
        ]
        try Self.write(Self.rollout(keptPrefix + [
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(
                total: keptTurn + revertedTurn,
                last: revertedTurn,
                timestamp: startedAt + 120,
                ordinal: 4
            ),
        ]), to: originalFile)
        try Self.write(Self.rollout([
            Self.sessionMeta(
                id: threadID,
                timestamp: startedAt + 1_800,
                paginated: true,
                historyBase: HistoryBase(
                    rolloutID: threadID,
                    endOrdinalExclusive: keptPrefix.count,
                    endByteOffset: Data(Self.rollout(keptPrefix).utf8).count
                )
            ),
            Self.settingsApplied(threadID: threadID, timestamp: startedAt + 1_860, ordinal: 1),
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(
                total: keptTurn + turnAfterRevert,
                last: turnAfterRevert,
                timestamp: startedAt + 1_920,
                ordinal: 3
            ),
        ]), to: revertFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 101)
        let entries = try await source.fetchEntries(since: .distantPast)
        let original = try #require(entries.first { $0.dedupKey == "codex:\(threadID)" })
        let revert = try #require(entries.first { $0.dedupKey == "codex:\(revertRolloutID)" })

        // The reverted turn was still billed, so the original rollout keeps it.
        #expect(original.tokens.cacheReadTokens == 8_000)
        #expect(revert.sessionID == threadID)
        #expect(revert.tokens.inputTokens == 500)
        #expect(revert.tokens.cacheReadTokens == 2_500)
        #expect(revert.tokens.outputTokens == 280)
        #expect(revert.tokens.reasoningTokens == 120)
    }

    @Test func forkWithoutItsSettingsRecordKeepsItsTotal() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a006"
        let forkID = "019f8a10-0000-7000-8000-00000000f006"
        let forkFile = directory.appendingPathComponent("rollout-2026-06-01T08-00-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_780_300_000)
        let inherited = Usage(input: 4_000, cached: 1_000, output: 400, reasoning: 100)
        let forkTurn = Usage(input: 2_000, cached: 500, output: 300, reasoning: 50)

        // Codex releases before late August 2026 did not mark where copied history ends,
        // and resuming such a fork later records its settings after its own usage.
        try Self.write(Self.rollout([
            Self.sessionMeta(id: forkID, timestamp: forkedAt, forkedFromID: parentID),
            Self.codexTokenCount(total: inherited, last: inherited, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.4"),
            Self.codexTokenCount(total: inherited + forkTurn, last: forkTurn, timestamp: forkedAt + 300),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt + 86_400),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory])
        let fork = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(fork.tokens.inputTokens == 4_500)
        #expect(fork.tokens.cacheReadTokens == 1_500)
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexLogSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ content: String, to url: URL) throws {
        try Data(content.utf8).write(to: url)
    }

    private static func append(_ content: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
    }

    private static func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private static func modificationDate(of url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return try #require(values.contentModificationDate)
    }

    private static func turnContext(model: String, effort: String? = nil) -> String {
        if let effort {
            return #"{"type":"turn_context","payload":{"model":"\#(model)","effort":"\#(effort)"}}"#
        }
        return #"{"type":"turn_context","payload":{"model":"\#(model)"}}"#
    }

    private static func tokenCount(
        timestamp: Date,
        input: Int,
        cached: Int = 0,
        output: Int = 0,
        reasoning: Int = 0
    ) -> String {
        let timestampString = ISO8601DateFormatter().string(from: timestamp)
        return #"{"timestamp":"\#(timestampString)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning)}}}}"#
    }

    private static func tokenCountWithoutTimestamp(input: Int) -> String {
        #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input)}}}}"#
    }

    // MARK: codex-rs rollout records

    /// `TokenUsage` as codex-rs serializes it. `total_tokens` is input plus output,
    /// except after a context-window reset.
    private struct Usage {
        let input: Int
        let cached: Int
        let output: Int
        let reasoning: Int
        let total: Int

        init(input: Int = 0, cached: Int = 0, output: Int = 0, reasoning: Int = 0, total: Int? = nil) {
            self.input = input
            self.cached = cached
            self.output = output
            self.reasoning = reasoning
            self.total = total ?? input + output
        }

        /// The empty total Codex writes when a request overflows the context window.
        static func contextWindowReset(_ window: Int) -> Usage {
            Usage(total: window)
        }

        static func + (lhs: Usage, rhs: Usage) -> Usage {
            Usage(
                input: lhs.input + rhs.input,
                cached: lhs.cached + rhs.cached,
                output: lhs.output + rhs.output,
                reasoning: lhs.reasoning + rhs.reasoning,
                total: lhs.total + rhs.total
            )
        }

        var json: String {
            #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"#
                + #""output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(total)}"#
        }
    }

    /// `HistoryPosition`: the prefix of another rollout a paginated thread continues from.
    private struct HistoryBase {
        let rolloutID: String
        let endOrdinalExclusive: Int
        let endByteOffset: Int
    }

    private static func rollout(_ records: [String]) -> String {
        records.joined(separator: "\n") + "\n"
    }

    /// `RolloutLine`: paginated rollouts also number every record.
    private static func record(
        type: String,
        payload: String,
        timestamp: Date,
        ordinal: Int?
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ordinalField = ordinal.map { #""ordinal":\#($0),"# } ?? ""
        return #"{"timestamp":"\#(formatter.string(from: timestamp))",\#(ordinalField)"type":"\#(type)","payload":\#(payload)}"#
    }

    private static func sessionMeta(
        id: String,
        timestamp: Date,
        forkedFromID: String? = nil,
        paginated: Bool = false,
        historyBase: HistoryBase? = nil
    ) -> String {
        let forkField = forkedFromID.map { #""forked_from_id":"\#($0)","# } ?? ""
        let historyMode = paginated ? "paginated" : "legacy"
        let historyBaseField = historyBase.map {
            #","history_base":{"thread_id":"\#($0.rolloutID)","end_ordinal_exclusive":\#($0.endOrdinalExclusive),"#
                + #""end_byte_offset":\#($0.endByteOffset)}"#
        } ?? ""
        let payload = #"{"session_id":"\#(id)","id":"\#(id)",\#(forkField)"timestamp":"2026-09-20T10:00:00.000Z","#
            + #""cwd":"/Users/dev/project","originator":"codex_cli_rs","cli_version":"0.140.0","source":"cli","#
            + #""model_provider":"openai","base_instructions":{"text":"You are Codex, a coding agent."},"#
            + #""history_mode":"\#(historyMode)"\#(historyBaseField)}"#
        return record(type: "session_meta", payload: payload, timestamp: timestamp, ordinal: paginated ? 0 : nil)
    }

    private static func codexTokenCount(
        total: Usage,
        last: Usage,
        timestamp: Date,
        ordinal: Int? = nil
    ) -> String {
        let payload = #"{"type":"token_count","info":{"total_token_usage":\#(total.json),"#
            + #""last_token_usage":\#(last.json),"model_context_window":272000},"rate_limits":null}"#
        return record(type: "event_msg", payload: payload, timestamp: timestamp, ordinal: ordinal)
    }

    private static func settingsApplied(
        threadID: String,
        timestamp: Date,
        ordinal: Int? = nil
    ) -> String {
        let payload = #"{"type":"thread_settings_applied","thread_id":"\#(threadID)","thread_settings":{"#
            + #""model":"gpt-5.5","model_provider_id":"openai","approval_policy":"on-request","#
            + #""approvals_reviewer":"user","permission_profile":{"type":"disabled"},"cwd":"/Users/dev/project","#
            + #""reasoning_effort":"high","#
            + #""collaboration_mode":{"mode":"default","settings":{"model":"gpt-5.5","reasoning_effort":"high"}},"#
            + #""disabled_plugin_ids":[]}}"#
        return record(type: "event_msg", payload: payload, timestamp: timestamp, ordinal: ordinal)
    }

    private static func functionCallOutput(byteCount: Int, timestamp: Date) -> String {
        let output = String(repeating: "x", count: byteCount)
        let payload = #"{"type":"function_call_output","call_id":"call_1","output":"\#(output)"}"#
        return record(type: "response_item", payload: payload, timestamp: timestamp, ordinal: nil)
    }
}

// MARK: - Token usage records

extension CodexLogSourceTests {
    @Test func countsRemoteCompactionUsageFromTokenUsageRecords() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = "019f8c21-5d3e-7a10-9c4b-6e2f0d8a1b37"
        let file = directory.appendingPathComponent("rollout-2026-09-20T10-00-00-\(sessionID).jsonl")
        let start = Date(timeIntervalSince1970: 1_789_900_000)
        let first = Usage(input: 40_000, cached: 30_000, output: 2_000, reasoning: 500)
        let compaction = Usage(input: 180_000, cached: 150_000, output: 6_000, reasoning: 1_000)
        let second = Usage(input: 20_000, cached: 12_000, output: 1_500, reasoning: 300)
        let compactedThread = first + compaction
        let compactionRecord = Self.usageRecordPayload(
            threadID: sessionID,
            response: "resp-compact",
            usage: compaction,
            turnUsage: compactedThread,
            threadUsage: compactedThread
        )
        try Self.write(Self.rollout([
            Self.functionCallOutput(byteCount: 1_024 * 1_024, timestamp: start),
            Self.turnContext(model: "gpt-5.5-codex", effort: "high"),
            Self.usageRecord(threadID: sessionID, response: "resp-1", usage: first, threadUsage: first, timestamp: start),
            Self.codexTokenCount(total: first, last: first, timestamp: start),
            // `compact_remote_v2` reports the compaction response's usage only as a record.
            Self.record(type: "token_usage_record", payload: compactionRecord, timestamp: start + 30, ordinal: nil),
            Self.compacted(latestRecordPayload: compactionRecord, timestamp: start + 30),
            // `recompute_token_usage` re-estimates `last_token_usage` and keeps the total.
            Self.codexTokenCount(total: first, last: Usage(total: 9_000), timestamp: start + 31),
            Self.usageRecord(
                threadID: sessionID,
                response: "resp-2",
                usage: second,
                turnUsage: compactedThread + second,
                threadUsage: compactedThread + second,
                timestamp: start + 60
            ),
            Self.codexTokenCount(total: first + second, last: second, timestamp: start + 60),
        ]), to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 4 * 1_024)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)
        let diagnostics = await source.latestDiagnostics()

        #expect(Self.reported(entry.tokens) == Self.reported(compactedThread + second))
        #expect(entry.model == "gpt-5.5-codex")
        #expect(entry.effortLevel?.rawValue == "high")
        #expect(entry.timestamp == start + 60)
        #expect(entry.dedupKey == "codex:\(sessionID)")
        // The newest record is in the newest turn, so earlier history stays unread.
        #expect(diagnostics.bytesRead < 64 * 1_024)
    }

    @Test func keepsRecordedUsageAcrossContextWindowResets() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = "019f8c21-5d3e-7a10-9c4b-6e2f0d8a1b38"
        let file = directory.appendingPathComponent("rollout-2026-09-20T11-00-00-\(sessionID).jsonl")
        let start = Date(timeIntervalSince1970: 1_789_900_000)
        // An overflowing request fills `total_token_usage` to the context window with no
        // priced counters (`set_total_tokens_full`). Records are left alone.
        let reset = Usage.contextWindowReset(272_000)
        let first = Usage(input: 150_000, cached: 120_000, output: 4_000, reasoning: 1_000)
        let second = Usage(input: 30_000, cached: 10_000, output: 2_000, reasoning: 400)
        try Self.write(Self.rollout([
            Self.turnContext(model: "gpt-5.5-codex"),
            Self.usageRecord(threadID: sessionID, response: "resp-1", usage: first, threadUsage: first, timestamp: start),
            Self.codexTokenCount(total: first, last: first, timestamp: start),
            Self.codexTokenCount(total: reset, last: Usage(total: reset.total - first.total), timestamp: start + 10),
            Self.turnContext(model: "gpt-5.5-codex"),
            Self.usageRecord(
                threadID: sessionID,
                turn: "turn-2",
                response: "resp-2",
                usage: second,
                threadUsage: first + second,
                timestamp: start + 60
            ),
            Self.codexTokenCount(total: reset + second, last: second, timestamp: start + 60),
            // The final turn's first request overflows as well, so that turn has no record.
            Self.turnContext(model: "gpt-5.5-codex"),
            Self.codexTokenCount(total: reset, last: Usage(total: 0), timestamp: start + 120),
        ]), to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 97)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(Self.reported(entry.tokens) == Self.reported(first + second))
        #expect(entry.timestamp == start + 120)
    }

    @Test func legacyRolloutKeepsTokenCountTotalWithinNewestTurn() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-legacy.jsonl")
        let start = Date(timeIntervalSince1970: 1_752_969_600)
        let first = Usage(input: 12_000, cached: 4_000, output: 900, reasoning: 200)
        let second = Usage(input: 8_000, cached: 6_000, output: 600, reasoning: 100)
        try Self.write(Self.rollout([
            Self.turnContext(model: "gpt-5-codex", effort: "high"),
            Self.functionCallOutput(byteCount: 1_024 * 1_024, timestamp: start),
            Self.codexTokenCount(total: first, last: first, timestamp: start),
            Self.turnContext(model: "gpt-5-codex", effort: "medium"),
            Self.codexTokenCount(total: first + second, last: second, timestamp: start + 60),
        ]), to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 4 * 1_024)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)
        let diagnostics = await source.latestDiagnostics()

        #expect(Self.reported(entry.tokens) == Self.reported(first + second))
        #expect(entry.effortLevel?.rawValue == "medium")
        #expect(entry.timestamp == start + 60)
        // The search for a record ends at the newest turn's `turn_context`.
        #expect(diagnostics.bytesRead < 64 * 1_024)
    }

    @Test func resumedSessionKeepsUsageFromBeforeRecords() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = "019f8c21-5d3e-7a10-9c4b-6e2f0d8a1b39"
        let file = directory.appendingPathComponent("rollout-2026-08-20T09-00-00-\(sessionID).jsonl")
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let earlier = Usage(input: 90_000, cached: 70_000, output: 5_000, reasoning: 1_200)
        let resumed = Usage(input: 15_000, cached: 9_000, output: 800, reasoning: 150)
        try Self.write(Self.rollout([
            // Written by a Codex without records.
            Self.turnContext(model: "gpt-5.5-codex"),
            Self.codexTokenCount(total: earlier, last: earlier, timestamp: start),
            // A newer Codex resumes it: `token_count` continues from the rollout's total,
            // while records start at zero because the rollout has none to continue from.
            Self.turnContext(model: "gpt-5.5-codex"),
            Self.usageRecord(
                threadID: sessionID,
                turn: "turn-2",
                response: "resp-2",
                usage: resumed,
                threadUsage: resumed,
                timestamp: start + 86_400
            ),
            Self.codexTokenCount(total: earlier + resumed, last: resumed, timestamp: start + 86_400),
        ]), to: file)

        let source = CodexLogSource(directories: [directory], readChunkSize: 53)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(Self.reported(entry.tokens) == Self.reported(earlier + resumed))
    }

    @Test func copiedForkSubtractsItsCopiedRecordTotal() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a011"
        let forkID = "019f8a10-0000-7000-8000-00000000f011"
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T14-00-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_010_000)
        let inherited = Usage(input: 60_000, cached: 40_000, output: 3_000, reasoning: 900)
        let compaction = Usage(input: 70_000, cached: 50_000, output: 4_000, reasoning: 700)
        let forkTurn = Usage(input: 9_000, cached: 6_000, output: 800, reasoning: 250)

        try Self.write(Self.rollout([
            Self.sessionMeta(id: forkID, timestamp: forkedAt, forkedFromID: parentID),
            // `/fork` copies the parent's records, its usage records included, so Codex
            // seeds the fork's records with the parent's thread total.
            Self.turnContext(model: "gpt-5.5"),
            Self.usageRecord(
                threadID: parentID,
                response: "resp-parent",
                usage: inherited,
                threadUsage: inherited,
                timestamp: forkedAt
            ),
            Self.codexTokenCount(total: inherited, last: inherited, timestamp: forkedAt),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.5"),
            Self.usageRecord(
                threadID: forkID,
                turn: "turn-fork",
                response: "resp-compact",
                usage: compaction,
                threadUsage: inherited + compaction,
                timestamp: forkedAt + 60
            ),
            Self.codexTokenCount(total: inherited, last: Usage(total: 20_000), timestamp: forkedAt + 61),
            Self.usageRecord(
                threadID: forkID,
                turn: "turn-fork",
                response: "resp-fork",
                usage: forkTurn,
                turnUsage: compaction + forkTurn,
                threadUsage: inherited + compaction + forkTurn,
                timestamp: forkedAt + 120
            ),
            Self.codexTokenCount(total: inherited + forkTurn, last: forkTurn, timestamp: forkedAt + 120),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 97)
        let fork = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(Self.reported(fork.tokens) == Self.reported(compaction + forkTurn))
        #expect(fork.timestamp == forkedAt + 120)
    }

    @Test func forkedSubagentRecordsStartFromZero() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a012"
        let childID = "019f8a10-0000-7000-8000-00000000f012"
        let childFile = directory.appendingPathComponent("rollout-2026-09-20T15-00-00-\(childID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_020_000)
        // Smaller than the child's usage in every counter, so subtracting it by mistake shows.
        let parent = Usage(input: 2_000, cached: 1_000, output: 200, reasoning: 50)
        let compaction = Usage(input: 50_000, cached: 40_000, output: 3_000, reasoning: 600)
        let child = Usage(input: 25_000, cached: 20_000, output: 1_200, reasoning: 300)
        let subagentMeta = Self.sessionMeta(id: childID, timestamp: forkedAt, forkedFromID: parentID)
            .replacingOccurrences(
                of: #""source":"cli""#,
                with: #""source":{"subagent":{"thread_spawn":{"parent_thread_id":"\#(parentID)"}}},"#
                    + #""thread_source":"subagent""#
            )

        try Self.write(Self.rollout([
            subagentMeta,
            // A forked spawn copies the parent's `token_count` but drops its usage records.
            Self.turnContext(model: "gpt-5.5"),
            Self.codexTokenCount(total: parent, last: parent, timestamp: forkedAt),
            Self.settingsApplied(threadID: childID, timestamp: forkedAt),
            Self.turnContext(model: "gpt-5.5-codex-mini"),
            Self.usageRecord(
                threadID: childID,
                turn: "turn-child",
                response: "resp-compact",
                usage: compaction,
                threadUsage: compaction,
                timestamp: forkedAt + 30
            ),
            Self.codexTokenCount(total: parent, last: Usage(total: 15_000), timestamp: forkedAt + 31),
            Self.usageRecord(
                threadID: childID,
                turn: "turn-child",
                response: "resp-child",
                usage: child,
                turnUsage: compaction + child,
                threadUsage: compaction + child,
                timestamp: forkedAt + 60
            ),
            Self.codexTokenCount(total: parent + child, last: child, timestamp: forkedAt + 60),
        ]), to: childFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 61)
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(Self.reported(entry.tokens) == Self.reported(compaction + child))
        #expect(entry.model == "gpt-5.5-codex-mini")
        #expect(entry.isSubagentSession)
    }

    @Test func referencedForkSubtractsRecordTotalAtForkPoint() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parentID = "019f8a10-0000-7000-8000-00000000a013"
        let forkID = "019f8a10-0000-7000-8000-00000000f013"
        let parentFile = directory.appendingPathComponent("rollout-2026-09-20T16-00-00-\(parentID).jsonl")
        let forkFile = directory.appendingPathComponent("rollout-2026-09-20T16-30-00-\(forkID).jsonl")
        let forkedAt = Date(timeIntervalSince1970: 1_790_030_000)
        let firstTurn = Usage(input: 5_000, cached: 1_000, output: 600, reasoning: 200)
        let parentCompaction = Usage(input: 80_000, cached: 60_000, output: 5_000, reasoning: 800)
        let secondTurn = Usage(input: 7_000, cached: 5_000, output: 900, reasoning: 400)
        let inheritedRecord = firstTurn + parentCompaction + secondTurn
        let parentAfterFork = Usage(input: 3_000, cached: 2_000, output: 100, reasoning: 50)
        let forkTurn = Usage(input: 8_000, cached: 6_000, output: 1_200, reasoning: 700)

        let parentPrefix = [
            Self.sessionMeta(id: parentID, timestamp: forkedAt - 900, paginated: true),
            Self.settingsApplied(threadID: parentID, timestamp: forkedAt - 900, ordinal: 1),
            Self.turnContext(model: "gpt-5.5"),
            Self.usageRecord(
                threadID: parentID,
                response: "resp-1",
                usage: firstTurn,
                threadUsage: firstTurn,
                timestamp: forkedAt - 840,
                ordinal: 3
            ),
            Self.codexTokenCount(total: firstTurn, last: firstTurn, timestamp: forkedAt - 840, ordinal: 4),
            Self.usageRecord(
                threadID: parentID,
                response: "resp-compact",
                usage: parentCompaction,
                threadUsage: firstTurn + parentCompaction,
                timestamp: forkedAt - 800,
                ordinal: 5
            ),
            Self.usageRecord(
                threadID: parentID,
                response: "resp-2",
                usage: secondTurn,
                threadUsage: inheritedRecord,
                timestamp: forkedAt - 780,
                ordinal: 6
            ),
            Self.codexTokenCount(
                total: firstTurn + secondTurn,
                last: secondTurn,
                timestamp: forkedAt - 780,
                ordinal: 7
            ),
        ]
        try Self.write(Self.rollout(parentPrefix + [
            Self.turnContext(model: "gpt-5.5"),
            Self.usageRecord(
                threadID: parentID,
                turn: "turn-2",
                response: "resp-3",
                usage: parentAfterFork,
                threadUsage: inheritedRecord + parentAfterFork,
                timestamp: forkedAt + 300,
                ordinal: 9
            ),
            Self.codexTokenCount(
                total: firstTurn + secondTurn + parentAfterFork,
                last: parentAfterFork,
                timestamp: forkedAt + 300,
                ordinal: 10
            ),
        ]), to: parentFile)
        try Self.write(Self.rollout([
            Self.sessionMeta(
                id: forkID,
                timestamp: forkedAt,
                forkedFromID: parentID,
                paginated: true,
                historyBase: HistoryBase(
                    rolloutID: parentID,
                    endOrdinalExclusive: parentPrefix.count,
                    endByteOffset: Data(Self.rollout(parentPrefix).utf8).count
                )
            ),
            Self.settingsApplied(threadID: forkID, timestamp: forkedAt, ordinal: 1),
            Self.turnContext(model: "gpt-5.5"),
            Self.usageRecord(
                threadID: forkID,
                turn: "turn-fork",
                response: "resp-fork",
                usage: forkTurn,
                threadUsage: inheritedRecord + forkTurn,
                timestamp: forkedAt + 60,
                ordinal: 3
            ),
            Self.codexTokenCount(
                total: firstTurn + secondTurn + forkTurn,
                last: forkTurn,
                timestamp: forkedAt + 60,
                ordinal: 4
            ),
        ]), to: forkFile)

        let source = CodexLogSource(directories: [directory], readChunkSize: 89)
        let entries = try await source.fetchEntries(since: .distantPast)
        let parent = try #require(entries.first { $0.dedupKey == "codex:\(parentID)" })
        let fork = try #require(entries.first { $0.dedupKey == "codex:\(forkID)" })

        #expect(Self.reported(parent.tokens) == Self.reported(inheritedRecord + parentAfterFork))
        #expect(Self.reported(fork.tokens) == Self.reported(forkTurn))
    }

    /// The disjoint counts `CodexLogSource` reports for a Codex `TokenUsage`: uncached
    /// input, cached input, output without reasoning, and reasoning.
    private static func reported(_ usage: Usage) -> [Int] {
        [usage.input - usage.cached, usage.cached, usage.output - usage.reasoning, usage.reasoning]
    }

    private static func reported(_ tokens: TokenCount) -> [Int] {
        [tokens.inputTokens, tokens.cacheReadTokens, tokens.outputTokens, tokens.reasoningTokens]
    }

    /// `TokenUsageRecord`, which Codex writes after every completed response.
    private static func usageRecordPayload(
        threadID: String,
        turn: String = "turn-1",
        response: String,
        usage: Usage,
        turnUsage: Usage? = nil,
        threadUsage: Usage
    ) -> String {
        #"{"thread_id":"\#(threadID)","turn_id":"\#(turn)","session_id":"\#(threadID)","#
            + #""root_turn_id":"\#(turn)","response_id":"\#(response)","usage":\#(usage.json),"#
            + #""turn_token_usage":\#((turnUsage ?? usage).json),"thread_token_usage":\#(threadUsage.json)}"#
    }

    private static func usageRecord(
        threadID: String,
        turn: String = "turn-1",
        response: String,
        usage: Usage,
        turnUsage: Usage? = nil,
        threadUsage: Usage,
        timestamp: Date,
        ordinal: Int? = nil
    ) -> String {
        let payload = usageRecordPayload(
            threadID: threadID,
            turn: turn,
            response: response,
            usage: usage,
            turnUsage: turnUsage,
            threadUsage: threadUsage
        )
        return record(type: "token_usage_record", payload: payload, timestamp: timestamp, ordinal: ordinal)
    }

    /// A remote compaction checkpoint, which carries a copy of the newest usage record.
    private static func compacted(latestRecordPayload: String, timestamp: Date) -> String {
        let payload = #"{"message":"","replacement_history":[{"type":"compaction","encrypted_content":"SUMMARY"}],"#
            + #""window_number":2,"compaction_response_id":"resp-compact","#
            + #""latest_token_usage_record":\#(latestRecordPayload)}"#
        return record(type: "compacted", payload: payload, timestamp: timestamp, ordinal: nil)
    }

    // MARK: - Codex rollout records, shaped after codex-rs protocol types

    private static func codexDate(_ timestamp: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: timestamp))
    }

    /// `SessionMetaLine` as `codex exec` writes it: `SessionSource::Exec`, the
    /// `codex_exec` originator, and paginated history, whose records carry `ordinal`.
    private static func execSessionMeta(sessionID: String, timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":0,"type":"session_meta","payload":{"session_id":"\#(sessionID)","#
            + #""id":"\#(sessionID)","timestamp":"\#(timestamp)","cwd":"/Users/dev/project","originator":"codex_exec","#
            + #""cli_version":"0.0.0","source":"exec","thread_source":"user","model_provider":"openai","#
            + #""base_instructions":{"text":"You are Codex."},"history_mode":"paginated"}}"#
    }

    /// `TurnContextItem` with only its required fields plus `turn_id` and `effort`.
    private static func pagedTurnContext(
        timestamp: String,
        ordinal: Int,
        turnID: String = "turn-1",
        model: String,
        effort: String
    ) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":\#(ordinal),"type":"turn_context","payload":{"turn_id":"\#(turnID)","#
            + #""cwd":"/Users/dev/project","approval_policy":"never","sandbox_policy":{"type":"read-only"},"#
            + #""model":"\#(model)","effort":"\#(effort)","summary":"auto"}}"#
    }

    /// `TokenUsage`. The Responses API reports `total_tokens` as input plus output.
    private static func codexTokenUsage(
        input: Int,
        cached: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        total: Int? = nil
    ) -> String {
        let totalTokens = total ?? input + output
        return #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"#
            + #""output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(totalTokens)}"#
    }

    /// `EventMsg::TokenCount` with `TokenUsageInfo`.
    private static func pagedTokenCount(timestamp: String, ordinal: Int, total: String, last: String) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"token_count","#
            + #""info":{"total_token_usage":\#(total),"last_token_usage":\#(last),"model_context_window":272000},"#
            + #""rate_limits":\#(codexRateLimits)}}"#
    }

    /// `RolloutItem::TokenUsageRecord`, written once per completed response.
    private static func tokenUsageRecord(
        timestamp: String,
        ordinal: Int,
        sessionID: String,
        responseID: String,
        usage: String,
        threadUsage: String
    ) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":\#(ordinal),"type":"token_usage_record","payload":{"#
            + #""thread_id":"\#(sessionID)","turn_id":"turn-1","session_id":"\#(sessionID)","root_turn_id":"turn-1","#
            + #""response_id":"\#(responseID)","usage":\#(usage),"turn_token_usage":\#(threadUsage),"#
            + #""thread_token_usage":\#(threadUsage)}}"#
    }

    /// `RateLimitSnapshot` as serialized in codex-rs/rollout/src/tests.rs.
    private static let codexRateLimits: String = #"{"limit_id":null,"limit_name":null,"#
        + #""primary":{"used_percent":0.0,"window_minutes":60,"resets_at":1800000000},"#
        + #""secondary":{"used_percent":12.5,"window_minutes":10080,"resets_at":1800100000},"#
        + #""credits":null,"individual_limit":null,"spend_control_reached":null,"plan_type":null,"#
        + #""rate_limit_reached_type":null}"#
}

private final class SandboxDeniedFileManager: FileManager, @unchecked Sendable {
    private let deniedPath: String

    init(deniedDirectory: URL) {
        self.deniedPath = deniedDirectory.standardizedFileURL.path
        super.init()
    }

    override func fileExists(atPath path: String) -> Bool {
        guard standardizedPath(path) != deniedPath else {
            return false
        }
        return super.fileExists(atPath: path)
    }

    override func fileExists(
        atPath path: String,
        isDirectory: UnsafeMutablePointer<ObjCBool>?
    ) -> Bool {
        guard standardizedPath(path) != deniedPath else {
            isDirectory?.pointee = true
            return false
        }
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        guard url.standardizedFileURL.path != deniedPath else {
            throw CocoaError(.fileReadNoPermission)
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
#endif
