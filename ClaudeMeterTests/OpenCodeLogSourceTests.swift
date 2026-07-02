//
//  OpenCodeLogSourceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import ClaudeMeter
import ClaudeMeterKit

@Suite("OpenCode Log Source")
struct OpenCodeLogSourceTests {
    @Test func mapsOpenAIProviderIDToCodexBucket() throws {
        let model = OpenCodeLogSource.parseModel(#"{"id":"gpt-5.5","providerID":"openai"}"#)

        #expect(model.id == "gpt-5.5")
        #expect(model.providerID == "openai")
        #expect(model.provider == .codex)
    }

    @Test func parsesOpenCodeProviderIDsForPricing() throws {
        let goModel = OpenCodeLogSource.parseModel(#"{"id":"qwen3-coder","providerID":"opencode-go"}"#)
        let zenModel = OpenCodeLogSource.parseModel(#"{"id":"gpt-5.1-codex","providerID":"opencode-zen"}"#)

        #expect(goModel.providerID == "opencode-go")
        #expect(goModel.provider == .openCode)
        #expect(zenModel.providerID == "opencode-zen")
        #expect(zenModel.provider == .openCode)
    }

    @Test func routesOpenAIProviderIDToCodexRegardlessOfModel() throws {
        // The rule is providerID-based: a model served through an OpenAI-compatible
        // setup reporting providerID="openai" routes to Codex even if not a GPT model.
        let model = OpenCodeLogSource.parseModel(#"{"id":"glm-5.2","providerID":"openai"}"#)

        #expect(model.id == "glm-5.2")
        #expect(model.providerID == "openai")
        #expect(model.provider == .codex)
    }

    @Test func keepsGLMWithOpenCodeGoProviderInOpenCodeBucket() throws {
        // Real-world GLM sessions arrive via OpenCode Go (providerID="opencode-go").
        let model = OpenCodeLogSource.parseModel(#"{"id":"glm-5.2","providerID":"opencode-go"}"#)

        #expect(model.id == "glm-5.2")
        #expect(model.providerID == "opencode-go")
        #expect(model.provider == .openCode)
    }

    @Test func invalidModelJSONFallsBackWithoutOpenAIHardcoding() throws {
        let model = OpenCodeLogSource.parseModel("not-json")

        #expect(model.id == "not-json")
        #expect(model.providerID == "unknown")
        #expect(model.provider == .openCode)
    }

    @Test func sqliteRowsUseProviderIDForBucketAndPricingProvider() async throws {
        let root = try Self.temporaryDirectory()
        let database = root.appendingPathComponent("opencode.db")
        try Self.createSessionDatabase(
            at: database,
            modelJSON: #"{"id":"gpt-5.5","providerID":"openai"}"#
        )

        let source = OpenCodeLogSource(candidatePaths: [database])
        let entries = try await source.fetchEntries(since: Date(timeIntervalSince1970: 0))
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.provider == .codex)
        #expect(entry.pricingProviderKey == "openai")
        #expect(entry.model == "gpt-5.5")
        #expect(entry.tokens.inputTokens == 100)
        #expect(entry.tokens.outputTokens == 40)
        #expect(entry.tokens.reasoningTokens == 10)
        #expect(entry.tokens.cacheReadTokens == 30)
        #expect(entry.tokens.cacheCreationTokens == 20)
    }

    @Test func extraProviderDetailsAggregateByEntryProviderNotSourceProvider() async throws {
        let source = StaticUsageLogSource(entries: [
            ProviderUsageEntry(
                provider: .codex,
                model: "gpt-5.5",
                pricingProviderKey: "openai",
                tokens: TokenCount(inputTokens: 100, outputTokens: 40, cacheCreationTokens: 20, cacheReadTokens: 30),
                timestamp: Date(),
                dedupKey: "opencode:openai-session"
            )
        ])
        let service = TokenUsageService(extraSources: [source])

        let details = await service.fetchExtraProviderDetails(since: Date(timeIntervalSince1970: 0))

        #expect(details[.codex]?.last30Days.tokens.totalTokens == 190)
        #expect(details[.openCode] == nil)
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeLogSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func createSessionDatabase(at url: URL, modelJSON: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw OpenCodeLogSourceTestError.sqliteOpenFailed
        }
        defer { sqlite3_close(database) }

        let createSQL = """
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            model TEXT NOT NULL,
            tokens_input INTEGER NOT NULL,
            tokens_output INTEGER NOT NULL,
            tokens_reasoning INTEGER NOT NULL,
            tokens_cache_read INTEGER NOT NULL,
            tokens_cache_write INTEGER NOT NULL,
            time_created INTEGER NOT NULL
        )
        """
        guard sqlite3_exec(database, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw OpenCodeLogSourceTestError.sqliteExecFailed
        }

        let escapedModel = modelJSON.replacingOccurrences(of: "'", with: "''")
        let insertSQL = """
        INSERT INTO session (
            id, model, tokens_input, tokens_output, tokens_reasoning,
            tokens_cache_read, tokens_cache_write, time_created
        ) VALUES (
            'session-1', '\(escapedModel)', 100, 40, 10, 30, 20, 1771952413521
        )
        """
        guard sqlite3_exec(database, insertSQL, nil, nil, nil) == SQLITE_OK else {
            throw OpenCodeLogSourceTestError.sqliteExecFailed
        }
    }
}

private enum OpenCodeLogSourceTestError: Error {
    case sqliteOpenFailed
    case sqliteExecFailed
}

private actor StaticUsageLogSource: UsageLogSource {
    nonisolated let provider: Provider = .openCode
    private let entries: [ProviderUsageEntry]

    init(entries: [ProviderUsageEntry]) {
        self.entries = entries
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        entries.filter { $0.timestamp >= since }
    }
}
#endif
