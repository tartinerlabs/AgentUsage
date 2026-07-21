//
//  CodexLogSourceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage

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
            Self.turnContext(model: "gpt-old"),
            Self.tokenCount(timestamp: oldTimestamp, input: 20, cached: 5, output: 8, reasoning: 2),
            "not-json",
            Self.tokenCount(timestamp: latestTimestamp, input: 100, cached: 30, output: 50, reasoning: 10),
            Self.turnContext(model: "gpt-latest"),
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
        #expect(diagnostics.bytesRead <= 4 * 1024)
        #expect(diagnostics.maximumBufferedBytes <= 4 * 1024)
        #expect(diagnostics.bytesRead < data.count / 1_000)
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

    private static func turnContext(model: String) -> String {
        #"{"type":"turn_context","payload":{"model":"\#(model)"}}"#
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
}
#endif
