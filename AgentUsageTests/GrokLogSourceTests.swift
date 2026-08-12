//
//  GrokLogSourceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@MainActor
@Suite("Grok Log Source")
struct GrokLogSourceTests {
    @Test func estimatesTokensFromPerTurnContextFill() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "019ff70f-a788-70e0-ad42-f52237f694ae"
        try Self.writeSession(
            in: root,
            id: sessionID,
            model: "grok-4.6",
            updatedAt: "2026-08-12T17:40:26Z",
            effort: "high",
            updates: [
                Self.update(promptID: "turn-a", totalTokens: 1_000, turnStartMs: 100),
                Self.update(promptID: "turn-a", totalTokens: 1_400, turnStartMs: 100),
                Self.update(promptID: "turn-b", totalTokens: 1_400, turnStartMs: 200),
                Self.update(promptID: "turn-b", totalTokens: 1_800, turnStartMs: 200),
            ]
        )

        let source = GrokLogSource(directories: [root], readChunkSize: 64)
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.provider == .grok)
        #expect(entry.model == "grok-4.6")
        #expect(entry.pricingProviderKey == "xai")
        #expect(entry.tokens.inputTokens == 1_000)
        #expect(entry.tokens.outputTokens == 800)
        #expect(entry.tokens.cacheReadTokens == 1_400)
        #expect(entry.dedupKey == "grok:\(sessionID)")
        #expect(entry.sessionID == sessionID)
        #expect(entry.effortLevel?.rawValue == "high")
        #expect(entry.isSubagentSession == false)
        #expect(abs(entry.timestamp.timeIntervalSince1970 - 1_786_556_426) < 1)
    }

    @Test func fallsBackToSignalsContextTokensWhenStreamHasNoFill() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSession(
            in: root,
            id: "signals-only",
            model: "grok-4.6",
            updatedAt: "2026-08-12T18:00:00Z",
            contextTokensUsed: 12_345,
            updates: [#"{"timestamp":1,"method":"session/update","params":{"update":{"sessionUpdate":"user_message_chunk"}}}"#]
        )

        let source = GrokLogSource(directories: [root])
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)

        #expect(entry.tokens.inputTokens == 12_345)
        #expect(entry.tokens.outputTokens == 0)
        #expect(entry.tokens.cacheReadTokens == 0)
    }

    @Test func marksSubagentSessionsFromSessionKind() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSession(
            in: root,
            id: "child",
            model: "grok-4.6",
            updatedAt: "2026-08-12T18:00:00Z",
            effort: "high",
            sessionKind: "subagent",
            contextTokensUsed: 50,
            updates: []
        )

        let source = GrokLogSource(directories: [root])
        let entry = try #require(try await source.fetchEntries(since: .distantPast).first)
        let samples = await TokenUsageService(extraSources: [source])
            .fetchExtraProviderEffortSamples(since: .distantPast)

        #expect(entry.isSubagentSession)
        #expect(samples.count == 1)
        #expect(samples.first?.isSubagentSession == true)
        #expect(EffortUsageAggregator.summaries(from: samples).isEmpty)
    }

    @Test func throwsUnavailableWhenSessionsRootIsMissing() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokLogSource-missing-\(UUID().uuidString)", isDirectory: true)
        let source = GrokLogSource(directories: [missing])

        await #expect(throws: UsageLogSourceError.self) {
            _ = try await source.fetchEntries(since: .distantPast)
        }
    }

    @Test func reusesCachedSessionUntilFingerprintChanges() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSession(
            in: root,
            id: "cached",
            model: "grok-4.6",
            updatedAt: "2026-08-12T18:00:00Z",
            contextTokensUsed: 10,
            updates: [
                Self.update(promptID: "turn-a", totalTokens: 10, turnStartMs: 1),
            ]
        )

        let source = GrokLogSource(directories: [root])
        _ = try await source.fetchEntries(since: .distantPast)
        let first = await source.latestDiagnostics()
        #expect(first.parsedSessionCount == 1)
        #expect(first.cacheHitCount == 0)

        _ = try await source.fetchEntries(since: .distantPast)
        let cached = await source.latestDiagnostics()
        #expect(cached.parsedSessionCount == 0)
        #expect(cached.cacheHitCount == 1)

        try Self.writeSession(
            in: root,
            id: "cached",
            model: "grok-4.6",
            updatedAt: "2026-08-12T19:00:00Z",
            contextTokensUsed: 20,
            updates: [
                Self.update(promptID: "turn-a", totalTokens: 20, turnStartMs: 1),
            ]
        )
        let entries = try await source.fetchEntries(since: .distantPast)
        let second = await source.latestDiagnostics()
        #expect(second.parsedSessionCount == 1)
        #expect(second.cacheHitCount == 0)
        #expect(entries.first?.tokens.inputTokens == 20)
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokLogSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private static func writeSession(
        in root: URL,
        id: String,
        model: String,
        updatedAt: String,
        effort: String? = nil,
        sessionKind: String? = nil,
        contextTokensUsed: Int? = nil,
        updates: [String]
    ) throws -> URL {
        let directory = root
            .appendingPathComponent("%2Ftmp%2Fproject", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var summary: [String: Any] = [
            "info": ["id": id, "cwd": "/tmp/project"],
            "current_model_id": model,
            "updated_at": updatedAt,
        ]
        if let effort {
            summary["reasoning_effort"] = effort
        }
        if let sessionKind {
            summary["session_kind"] = sessionKind
        }
        try JSONSerialization.data(withJSONObject: summary).write(
            to: directory.appendingPathComponent("summary.json")
        )

        if let contextTokensUsed {
            try JSONSerialization.data(withJSONObject: ["contextTokensUsed": contextTokensUsed]).write(
                to: directory.appendingPathComponent("signals.json")
            )
        }

        let updatesURL = directory.appendingPathComponent("updates.jsonl")
        if updates.isEmpty {
            try Data().write(to: updatesURL)
        } else {
            try (updates.joined(separator: "\n") + "\n").write(to: updatesURL, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private static func update(promptID: String, totalTokens: Int, turnStartMs: Int) -> String {
        """
        {"timestamp":1,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"},"_meta":{"totalTokens":\(totalTokens),"promptId":"\(promptID)","turnStartMs":\(turnStartMs)}}}
        """
    }
}
#endif
