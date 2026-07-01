//
//  CodexLogSourceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import Testing
@testable import ClaudeMeter
import ClaudeMeterKit

@Suite("Codex Log Source")
struct CodexLogSourceTests {
    /// `~/.codex/sessions/<y>/<m>/<d>/rollout-*.jsonl` is the real layout, but the
    /// enumerator walks recursively, so a flat temp dir of `rollout-*.jsonl` files
    /// exercises the same parsing path without needing the year/month/day nesting.
    @Test func parsesTokenCountDisjointSplit() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-disjoint", lines: [
            Self.sessionMeta(id: "sess-1"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 1000, cached: 200, output: 500, reasoning: 50)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        #expect(entry.provider == .codex)
        #expect(entry.model == "gpt-5-codex")
        // input 1000 - cached 200 = 800 ; output 500 - reasoning 50 = 450
        #expect(entry.tokens.inputTokens == 800)
        #expect(entry.tokens.outputTokens == 450)
        #expect(entry.tokens.cacheReadTokens == 200)
        #expect(entry.tokens.reasoningTokens == 50)
        #expect(entry.tokens.cacheCreationTokens == 0)
        #expect(entry.dedupKey == "codex:sess-1")
        #expect(entry.timestamp == Self.date("2026-01-01T00:00:00Z"))
    }

    @Test func keepsLastTokenCountEventWhenMultiple() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-multi", lines: [
            Self.sessionMeta(id: "sess-2"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 1000, cached: 0, output: 100, reasoning: 0),
            Self.tokenCount(timestamp: "2026-01-01T00:05:00Z", input: 3000, cached: 0, output: 200, reasoning: 0)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        // The last token_count event wins (cumulative totals).
        #expect(entry.tokens.inputTokens == 3000)
        #expect(entry.tokens.outputTokens == 200)
        #expect(entry.timestamp == Self.date("2026-01-01T00:05:00Z"))
    }

    @Test func fallsBackToFileModificationDateWhenTimestampMissing() async throws {
        let dir = try Self.makeRolloutDir()
        let url = try Self.writeRollout(dir: dir, name: "rollout-nots", lines: [
            Self.sessionMeta(id: "sess-3"),
            Self.turnContext(model: "gpt-5-codex"),
            // token_count with no top-level `timestamp` field
            Self.tokenCountNoTimestamp(input: 500, cached: 0, output: 50, reasoning: 0)
        ])
        let modDate = try #require(
            try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        #expect(abs(entry.timestamp.timeIntervalSince(modDate)) < 1)
    }

    @Test func fallsBackToFilenameWhenSessionMetaMissing() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-nometa", lines: [
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 100, cached: 0, output: 10, reasoning: 0)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        // No session_meta -> dedupKey uses the file's stem (rollout-nometa).
        #expect(entry.dedupKey == "codex:rollout-nometa")
    }

    @Test func usesDefaultModelWhenTurnContextMissing() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-nomodel", lines: [
            Self.sessionMeta(id: "sess-5"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 100, cached: 0, output: 10, reasoning: 0)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        #expect(entry.model == "gpt-5-codex")
    }

    @Test func skipsFileWithoutTokenCountEvent() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-notokens", lines: [
            Self.sessionMeta(id: "sess-6"),
            Self.turnContext(model: "gpt-5-codex")
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        #expect(entries.isEmpty)
    }

    @Test func skipsMalformedJSONLinesAndParsesValidOne() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-mixed", lines: [
            "this is not json",
            "{not valid either",
            Self.sessionMeta(id: "sess-7"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 222, cached: 0, output: 22, reasoning: 0)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        let entry = try #require(entries.first)
        #expect(entry.tokens.inputTokens == 222)
        #expect(entry.dedupKey == "codex:sess-7")
    }

    @Test func aggregatesAcrossMultipleFiles() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-a", lines: [
            Self.sessionMeta(id: "sess-a"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 100, cached: 0, output: 10, reasoning: 0)
        ])
        try Self.writeRollout(dir: dir, name: "rollout-b", lines: [
            Self.sessionMeta(id: "sess-b"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-02T00:00:00Z", input: 200, cached: 0, output: 20, reasoning: 0)
        ])

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        #expect(entries.count == 2)
        #expect(Set(entries.map(\.dedupKey)) == ["codex:sess-a", "codex:sess-b"])
    }

    @Test func ignoresNonRolloutFiles() async throws {
        let dir = try Self.makeRolloutDir()
        try Self.writeRollout(dir: dir, name: "rollout-keep", lines: [
            Self.sessionMeta(id: "sess-keep"),
            Self.turnContext(model: "gpt-5-codex"),
            Self.tokenCount(timestamp: "2026-01-01T00:00:00Z", input: 100, cached: 0, output: 10, reasoning: 0)
        ])
        // A `.jsonl` file that isn't a rollout, and a rollout that isn't `.jsonl`.
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("other.jsonl"))
        try Data(Self.sessionMeta(id: "x").utf8).write(to: dir.appendingPathComponent("rollout-noext"))

        let source = CodexLogSource(directories: [dir])
        let entries = try await source.fetchEntries(since: .distantPast)

        #expect(entries.count == 1)
        #expect(entries.first?.dedupKey == "codex:sess-keep")
    }

    // MARK: - Helpers

    private static func makeRolloutDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexLogSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private static func writeRollout(dir: URL, name: String, lines: [String]) throws -> URL {
        let url = dir.appendingPathComponent("\(name).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func sessionMeta(id: String) -> String {
        "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}"
    }

    private static func turnContext(model: String) -> String {
        "{\"type\":\"turn_context\",\"payload\":{\"model\":\"\(model)\"}}"
    }

    private static func tokenCount(
        timestamp: String, input: Int, cached: Int, output: Int, reasoning: Int
    ) -> String {
        "{\"type\":\"event_msg\",\"timestamp\":\"\(timestamp)\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":\(reasoning)}}}}"
    }

    private static func tokenCountNoTimestamp(
        input: Int, cached: Int, output: Int, reasoning: Int
    ) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":\(reasoning)}}}}"
    }

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
    }
}
#endif
