//
//  BlogUsageSyncTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import AgentUsage

@Suite("Blog Usage Sync", .serialized)
struct BlogUsageSyncTests {
    @Test func claudeParserDedupesRepeatedMessages() throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        try """
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-sonnet-4-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":30,"cache_creation_input_tokens":20}}}
        {"type":"assistant","timestamp":"2026-06-02T10:00:01Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-sonnet-4-5","usage":{"input_tokens":999,"output_tokens":999,"cache_read_input_tokens":999,"cache_creation_input_tokens":999}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let parser = BlogUsageSourceParser(homeDirectory: home, environment: [:])
        let events = try parser.parseClaudeEvents()

        #expect(events.count == 1)
        #expect(events.first?.agent == "claude")
        #expect(events.first?.provider == "anthropic")
        #expect(events.first?.inputTokens == 100)
        #expect(events.first?.outputTokens == 50)
        #expect(events.first?.cacheReadTokens == 30)
        #expect(events.first?.cacheWriteTokens == 20)
        #expect(events.first?.reasoningTokens == 0)
    }

    @Test func claudeParserSkipsSyntheticModelRows() throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        try """
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-synthetic","message":{"id":"msg-synthetic","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        {"type":"assistant","timestamp":"2026-06-02T10:00:01Z","requestId":"req-real","message":{"id":"msg-real","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let parser = BlogUsageSourceParser(homeDirectory: home, environment: [:])
        let events = try parser.parseClaudeEvents()

        #expect(events.count == 1)
        #expect(events.first?.model == "claude-sonnet-4-5")
    }

    @Test func codexParserSplitsCachedAndReasoningTokens() throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".codex/sessions/2026/06", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("session.jsonl")
        try """
        {"timestamp":"2026-06-02T10:00:00Z","payload":{"model":"gpt-5"}}
        {"timestamp":"2026-06-02T10:01:00Z","payload":{"type":"token_count","id":"usage-1","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":700,"reasoning_output_tokens":200}}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let parser = BlogUsageSourceParser(homeDirectory: home, environment: [:])
        let events = try parser.parseCodexEvents()

        #expect(events.count == 1)
        #expect(events.first?.agent == "codex")
        #expect(events.first?.provider == "openai")
        #expect(events.first?.model == "gpt-5")
        #expect(events.first?.inputTokens == 750)
        #expect(events.first?.cacheReadTokens == 250)
        #expect(events.first?.outputTokens == 500)
        #expect(events.first?.reasoningTokens == 200)
        #expect(events.first?.cacheWriteTokens == 0)
    }

    @Test func openCodeParserMapsOpenCodeGoProviderModelTimestampAndTokens() throws {
        let root = try Self.temporaryDirectory()
        let dataHome = root.appendingPathComponent("xdg", isDirectory: true)
        let databaseDirectory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        let database = databaseDirectory.appendingPathComponent("opencode.db")
        try Self.createOpenCodeDatabase(at: database)

        let parser = BlogUsageSourceParser(
            homeDirectory: root,
            environment: ["XDG_DATA_HOME": dataHome.path],
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
        let events = try parser.parseOpenCodeEvents()

        #expect(events.count == 1)
        #expect(events.first?.agent == "opencode")
        #expect(events.first?.provider == "opencode-go")
        #expect(events.first?.model == "gpt-5.5")
        #expect(events.first?.timestamp == Date(timeIntervalSince1970: 1_771_952_413.521))
        #expect(events.first?.inputTokens == 100)
        #expect(events.first?.cacheReadTokens == 30)
        #expect(events.first?.cacheWriteTokens == 20)
        #expect(events.first?.outputTokens == 40)
        #expect(events.first?.reasoningTokens == 10)
    }

    @Test func openCodeParserPreservesOpenAIProviderID() throws {
        let root = try Self.temporaryDirectory()
        let dataHome = root.appendingPathComponent("xdg", isDirectory: true)
        let databaseDirectory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        let database = databaseDirectory.appendingPathComponent("opencode.db")
        try Self.createOpenCodeDatabase(at: database, providerID: "openai")

        let parser = BlogUsageSourceParser(
            homeDirectory: root,
            environment: ["XDG_DATA_HOME": dataHome.path]
        )
        let events = try parser.parseOpenCodeEvents()

        #expect(events.count == 1)
        #expect(events.first?.agent == "opencode")
        #expect(events.first?.provider == "openai")
        #expect(events.first?.model == "gpt-5.5")
    }

    @Test func parseAllSourcesCoversClaudeCodexAndOpenCodeGo() throws {
        let home = try Self.temporaryDirectory()

        let claudeDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try """
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}}
        """.write(to: claudeDirectory.appendingPathComponent("usage.jsonl"), atomically: true, encoding: .utf8)

        let codexDirectory = home.appendingPathComponent(".codex/sessions/2026/06", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-02T10:00:00Z","payload":{"model":"gpt-5"}}
        {"timestamp":"2026-06-02T10:01:00Z","payload":{"type":"token_count","id":"usage-1","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":25,"output_tokens":70,"reasoning_output_tokens":20}}}}
        """.write(to: codexDirectory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let dataHome = home.appendingPathComponent("xdg", isDirectory: true)
        let databaseDirectory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        try Self.createOpenCodeDatabase(at: databaseDirectory.appendingPathComponent("opencode.db"))

        let parser = BlogUsageSourceParser(
            homeDirectory: home,
            environment: ["XDG_DATA_HOME": dataHome.path]
        )

        let agentProviders = try parser.parseAllSources().map { event in
            "\(event.agent)/\(event.provider)"
        }

        #expect(Set(agentProviders) == ["claude/anthropic", "codex/openai", "opencode/opencode-go"])
    }

    @Test func aggregatorProducesExactPayloadShape() {
        let timestamp = ISO8601DateFormatter().date(from: "2026-06-02T10:00:00Z")!
        let events = [
            BlogUsageEvent(
                id: "a",
                timestamp: timestamp,
                agent: "claude",
                provider: "anthropic",
                model: "claude-sonnet-4-5",
                inputTokens: 10,
                outputTokens: 20,
                cacheReadTokens: 30,
                cacheWriteTokens: 40,
                reasoningTokens: 0
            ),
            BlogUsageEvent(
                id: "b",
                timestamp: timestamp,
                agent: "claude",
                provider: "anthropic",
                model: "claude-sonnet-4-5",
                inputTokens: 1,
                outputTokens: 2,
                cacheReadTokens: 3,
                cacheWriteTokens: 4,
                reasoningTokens: 5
            )
        ]

        let rows = BlogUsageAggregator(calendar: Calendar(identifier: .gregorian)).aggregate(events)

        #expect(rows == [
            BlogUsageIngestRow(
                date: "2026-06-02",
                agent: "claude",
                provider: "anthropic",
                model: "claude-sonnet-4-5",
                inputTokens: 11,
                outputTokens: 22,
                cacheReadTokens: 33,
                cacheWriteTokens: 44,
                reasoningTokens: 5,
                totalTokens: 115,
                costUsd: "0.000538",
                messages: 2
            )
        ])
    }

    @Test func aggregatorPricesCodexAutoReviewUsingOpenAICodexRates() {
        let timestamp = ISO8601DateFormatter().date(from: "2026-06-02T10:00:00Z")!
        let events = [
            BlogUsageEvent(
                id: "codex-review",
                timestamp: timestamp,
                agent: "codex",
                provider: "openai",
                model: "codex-auto-review",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 1_000_000,
                cacheWriteTokens: 0,
                reasoningTokens: 500_000
            )
        ]

        let rows = BlogUsageAggregator(calendar: Calendar(identifier: .gregorian)).aggregate(events)

        #expect(rows.first?.costUsd == "22.925000")
    }

    @Test func aggregatorPricesGPT55FastUsingPriorityRates() {
        let timestamp = ISO8601DateFormatter().date(from: "2026-06-02T10:00:00Z")!
        let events = [
            BlogUsageEvent(
                id: "fast",
                timestamp: timestamp,
                agent: "codex",
                provider: "openai",
                model: "gpt-5.5-fast",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 1_000_000,
                cacheWriteTokens: 0,
                reasoningTokens: 0
            )
        ]

        let rows = BlogUsageAggregator(calendar: Calendar(identifier: .gregorian)).aggregate(events)

        #expect(rows.first?.costUsd == "88.750000")
    }

    @Test func aggregatorLeavesUnknownModelsUnpriced() {
        let timestamp = ISO8601DateFormatter().date(from: "2026-06-02T10:00:00Z")!
        let events = [
            BlogUsageEvent(
                id: "unknown",
                timestamp: timestamp,
                agent: "opencode",
                provider: "unknown",
                model: "<synthetic>",
                inputTokens: 1,
                outputTokens: 1,
                cacheReadTokens: 1,
                cacheWriteTokens: 1,
                reasoningTokens: 1
            )
        ]

        let rows = BlogUsageAggregator(calendar: Calendar(identifier: .gregorian)).aggregate(events)

        #expect(rows.first?.costUsd == nil)
    }

    @Test func syncClientSendsBearerAuthAndWrappedRows() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlogUsageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = BlogUsageSyncClient(session: session)
        let row = BlogUsageIngestRow(
            date: "2026-06-02",
            agent: "claude",
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            inputTokens: 1,
            outputTokens: 2,
            cacheReadTokens: 3,
            cacheWriteTokens: 4,
            reasoningTokens: 5,
            totalTokens: 15,
            costUsd: nil,
            messages: 1
        )

        BlogUsageURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
            let body = try Self.requestBodyData(request)
            let rawPayload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let rawRows = try #require(rawPayload["rows"] as? [[String: Any]])
            let rawRow = try #require(rawRows.first)
            #expect(rawRow["costUsd"] is NSNull)

            let payload = try JSONDecoder().decode(BlogUsageIngestPayload.self, from: body)
            #expect(payload.rows == [row])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        try await client.post(rows: [row], endpoint: URL(string: "https://example.com/api/usage/ingest")!, token: "test-token")
    }

    @Test func syncClientThrowsUnauthorizedOnAuthFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlogUsageURLProtocol.self]
        let client = BlogUsageSyncClient(session: URLSession(configuration: configuration))
        BlogUsageURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        await #expect(throws: BlogUsageSyncError.self) {
            try await client.post(rows: [Self.minimalRow()], endpoint: URL(string: "https://example.com")!, token: "bad-token")
        }
    }

    @Test func serverValidationErrorsAreCompacted() {
        let detail = """
        {"error":"Validation failed","errors":[{"field":"rows.0.costUsd","message":"Invalid input"},{"field":"rows.1.costUsd","message":"Invalid input"},{"field":"rows.2.costUsd","message":"Invalid input"}]}
        """
        let error = BlogUsageSyncError.serverError(400, detail)

        #expect(error.localizedDescription == "Blog usage sync failed: invalid costUsd in 3 rows.")
    }

    @Test func serviceThrottlesPassiveSyncForFiveMinutesAndManualBypassesThrottle() async throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        try ("""
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """ + "\n").write(to: log, atomically: true, encoding: .utf8)

        let defaults = try #require(UserDefaults(suiteName: "BlogUsageSyncTests-\(UUID().uuidString)"))
        let posting = CountingPosting()
        let clock = MutableTestClock(date: Date(timeIntervalSince1970: 1_780_000_000))
        let keychainAccount = "BlogUsageSyncTests-\(UUID().uuidString)"
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("blog-usage-index.sqlite")
        )
        let service = BlogUsageSyncService(
            indexer: indexer,
            client: posting,
            defaults: defaults,
            keychainAccount: keychainAccount,
            oauthProvider: nil,
            now: { clock.now() }
        )
        defer { KeychainHelper.deleteString(account: keychainAccount) }
        await service.setEnabled(true)
        await service.setEndpointURLString("https://example.com/api/usage/ingest")
        await service.setToken("test-token")
        await posting.setError(BlogUsageSyncError.unauthorized)

        let failed = await service.syncIfNeeded()
        #expect(failed.state == BlogUsageSyncState.failed)
        #expect(await posting.callCount == 1)

        let skipped = await service.syncIfNeeded()
        #expect(skipped.state == BlogUsageSyncState.skipped)
        #expect(await posting.callCount == 1)

        clock.advance(by: 5 * 60)
        let retried = await service.syncIfNeeded()
        #expect(retried.state == BlogUsageSyncState.failed)
        #expect(await posting.callCount == 2)

        let manual = await service.syncNow()
        #expect(manual.state == BlogUsageSyncState.failed)
        #expect(await posting.callCount == 3)
    }

    @Test func indexerMatchesTheLegacyAggregateAcrossAllSources() async throws {
        let home = try Self.temporaryDirectory()
        let claudeDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let claudeLog = claudeDirectory.appendingPathComponent("usage.jsonl")
        try [
            Self.claudeLine(id: "shared", inputTokens: 10),
            Self.claudeLine(id: "shared", inputTokens: 999),
            Self.claudeLine(id: "unique", inputTokens: 20)
        ].joined(separator: "\n").appending("\n")
            .write(to: claudeLog, atomically: true, encoding: .utf8)

        let codexDirectory = home.appendingPathComponent(".codex/sessions/2026/06", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let codexLog = codexDirectory.appendingPathComponent("session.jsonl")
        try [
            Self.codexModelLine(model: "gpt-5"),
            Self.codexUsageLine(id: "same-id", inputTokens: 100),
            Self.codexUsageLine(id: "same-id", inputTokens: 200)
        ].joined(separator: "\n").appending("\n")
            .write(to: codexLog, atomically: true, encoding: .utf8)

        let dataHome = home.appendingPathComponent("xdg", isDirectory: true)
        let openCodeDirectory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: openCodeDirectory, withIntermediateDirectories: true)
        try Self.createOpenCodeDatabase(at: openCodeDirectory.appendingPathComponent("opencode.db"))

        let parser = BlogUsageSourceParser(
            homeDirectory: home,
            environment: ["XDG_DATA_HOME": dataHome.path]
        )
        let expected = BlogUsageAggregator().aggregate(try parser.parseAllSources())
        let indexer = BlogUsageSourceIndexer(
            parser: parser,
            databaseURL: home.appendingPathComponent("index.sqlite")
        )

        let result = try await indexer.index(maximumBytes: 8 * 1_024 * 1_024)

        #expect(!result.isBackfillInProgress)
        #expect(try await indexer.rows() == expected)
    }

    @Test func indexerBoundsOversizedRecordsResumesAndSkipsWarmPayloadReads() async throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        let padding = String(repeating: "x", count: 300_000)
        let lines = (1...3).map { Self.claudeLine(id: "msg-\($0)", inputTokens: $0, padding: padding) }
        try lines.joined(separator: "\n").appending("\n")
            .write(to: log, atomically: true, encoding: .utf8)
        let largestRecordBytes = Data(lines[0].utf8).count + 1
        let budget = 64 * 1_024
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )

        let first = try await indexer.index(maximumBytes: budget)
        #expect(first.recordsProcessed == 1)
        #expect(first.bytesRead == largestRecordBytes)
        #expect(first.maximumBufferedBytes <= largestRecordBytes + BlogUsageSourceIndexer.readChunkSize)
        #expect(first.isBackfillInProgress)
        #expect(try await indexer.rows().first?.inputTokens == 1)

        let second = try await indexer.index(maximumBytes: budget)
        #expect(second.recordsProcessed == 1)
        #expect(second.bytesRead == largestRecordBytes)
        #expect(second.isBackfillInProgress)

        let third = try await indexer.index(maximumBytes: budget)
        #expect(third.recordsProcessed == 1)
        #expect(!third.isBackfillInProgress)
        #expect(try await indexer.rows().first?.inputTokens == 6)

        let warm = try await indexer.index(maximumBytes: budget)
        #expect(warm.bytesRead == 0)
        #expect(warm.recordsProcessed == 0)
        #expect(warm.changedRecords == 0)
    }

    @Test func indexerRetainsAnIncompleteFinalLineUntilItIsTerminated() async throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        let complete = Self.claudeLine(id: "complete", inputTokens: 10)
        let partial = Self.claudeLine(id: "partial", inputTokens: 20)
        try "\(complete)\n\(partial)".write(to: log, atomically: true, encoding: .utf8)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )

        let initial = try await indexer.index(maximumBytes: 1_024 * 1_024)
        #expect(initial.recordsProcessed == 1)
        #expect(try await indexer.rows().first?.inputTokens == 10)

        let unchanged = try await indexer.index(maximumBytes: 1_024 * 1_024)
        #expect(unchanged.bytesRead == 0)

        try Self.append("\n", to: log)
        let appended = try await indexer.index(maximumBytes: 1_024 * 1_024)
        #expect(appended.recordsProcessed == 1)
        #expect(try await indexer.rows().first?.inputTokens == 30)
    }

    @Test func movingACodexSessionToTheArchiveDoesNotDuplicateRecords() async throws {
        let home = try Self.temporaryDirectory()
        let sessions = home.appendingPathComponent(".codex/sessions/2026/06", isDirectory: true)
        let archive = home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let original = sessions.appendingPathComponent("session.jsonl")
        try [
            Self.codexModelLine(model: "gpt-5"),
            Self.codexUsageLine(id: "usage-1", inputTokens: 100),
            Self.codexUsageLine(id: "usage-2", inputTokens: 200)
        ].joined(separator: "\n").appending("\n")
            .write(to: original, atomically: true, encoding: .utf8)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )
        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)
        let before = try await indexer.rows()

        try FileManager.default.moveItem(at: original, to: archive.appendingPathComponent("session.jsonl"))
        let moved = try await indexer.index(maximumBytes: 1_024 * 1_024)

        #expect(moved.bytesRead == 0)
        #expect(try await indexer.rows() == before)
        #expect(try await indexer.rows().first?.messages == 2)
    }

    @Test func replacingAProcessedFileResetsItsIndexedPrefix() async throws {
        let home = try Self.temporaryDirectory()
        let logDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("usage.jsonl")
        try Self.claudeLine(id: "old", inputTokens: 1).appending("\n")
            .write(to: log, atomically: true, encoding: .utf8)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )
        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)

        try Self.claudeLine(id: "replacement", inputTokens: 50).appending("\n")
            .write(to: log, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: log.path
        )
        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)

        let row = try #require(try await indexer.rows().first)
        #expect(row.inputTokens == 50)
        #expect(row.messages == 1)
    }

    @Test func indexerPrioritizesNewestUnindexedFiles() async throws {
        let home = try Self.temporaryDirectory()
        let projectDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let older = projectDirectory.appendingPathComponent("older.jsonl")
        let newer = projectDirectory.appendingPathComponent("newer.jsonl")
        try Self.claudeLine(id: "older", inputTokens: 10).appending("\n")
            .write(to: older, atomically: true, encoding: .utf8)
        try Self.claudeLine(id: "newer", inputTokens: 20).appending("\n")
            .write(to: newer, atomically: true, encoding: .utf8)
        let baseline = Date(timeIntervalSince1970: 1_780_000_000)
        try FileManager.default.setAttributes([.modificationDate: baseline], ofItemAtPath: older.path)
        try FileManager.default.setAttributes(
            [.modificationDate: baseline.addingTimeInterval(60)],
            ofItemAtPath: newer.path
        )
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )

        let first = try await indexer.index(maximumBytes: 1)

        #expect(first.recordsProcessed == 1)
        #expect(first.isBackfillInProgress)
        #expect(try await indexer.rows().first?.inputTokens == 20)
    }

    @Test func indexerPrioritizesAppendsAheadOfNewBackfillFiles() async throws {
        let home = try Self.temporaryDirectory()
        let projectDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let indexed = projectDirectory.appendingPathComponent("indexed.jsonl")
        try Self.claudeLine(id: "base", inputTokens: 1).appending("\n")
            .write(to: indexed, atomically: true, encoding: .utf8)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )
        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)

        let unindexed = projectDirectory.appendingPathComponent("unindexed.jsonl")
        try Self.claudeLine(id: "backfill", inputTokens: 100).appending("\n")
            .write(to: unindexed, atomically: true, encoding: .utf8)
        try Self.append(Self.claudeLine(id: "append", inputTokens: 10).appending("\n"), to: indexed)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: indexed.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(60)],
            ofItemAtPath: unindexed.path
        )

        let next = try await indexer.index(maximumBytes: 1)

        #expect(next.recordsProcessed == 1)
        #expect(try await indexer.rows().first?.inputTokens == 11)
    }

    @Test func prunedLogsRetainTheirIndexedLifetimeUsage() async throws {
        let home = try Self.temporaryDirectory()
        let projectDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let log = projectDirectory.appendingPathComponent("usage.jsonl")
        try Self.claudeLine(id: "lifetime", inputTokens: 42).appending("\n")
            .write(to: log, atomically: true, encoding: .utf8)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )
        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)
        let before = try await indexer.rows()

        try FileManager.default.removeItem(at: log)
        let afterPrune = try await indexer.index(maximumBytes: 1_024 * 1_024)

        #expect(afterPrune.bytesRead == 0)
        #expect(try await indexer.rows() == before)
    }

    @Test func changingTimeZoneRebuildsTheDisposableIndex() throws {
        let root = try Self.temporaryDirectory()
        let databaseURL = root.appendingPathComponent("index.sqlite")
        let event = BlogUsageEvent(
            id: "event",
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            agent: "claude",
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            inputTokens: 1,
            outputTokens: 2,
            cacheReadTokens: 3,
            cacheWriteTokens: 4,
            reasoningTokens: 0
        )
        do {
            let store = try BlogUsageIndexStore(databaseURL: databaseURL, timeZoneIdentifier: "UTC")
            _ = try store.replaceRecord(
                source: .claude,
                container: "/tmp/log.jsonl",
                recordKey: "0",
                dedupeKey: "event",
                event: event
            )
            _ = try store.advanceRevision()
            #expect(try store.recordCount() == 1)
        }

        let rebuilt = try BlogUsageIndexStore(
            databaseURL: databaseURL,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        #expect(try rebuilt.recordCount() == 0)
        #expect(try rebuilt.revision() == 0)
    }

    @Test func corruptCacheIsReconstructed() throws {
        let root = try Self.temporaryDirectory()
        let databaseURL = root.appendingPathComponent("index.sqlite")
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        let store = try BlogUsageIndexStore(databaseURL: databaseURL, timeZoneIdentifier: "UTC")

        #expect(try store.recordCount() == 0)
        #expect(try store.revision() == 0)
    }

    @Test func persistenceFailureDoesNotAdvanceAFileCheckpoint() async throws {
        let home = try Self.temporaryDirectory()
        let projectDirectory = home.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try Self.claudeLine(id: "failure", inputTokens: 1).appending("\n")
            .write(
                to: projectDirectory.appendingPathComponent("usage.jsonl"),
                atomically: true,
                encoding: .utf8
            )
        let store = FailingBlogUsageIndexStore()
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            store: store
        )

        await #expect(throws: BlogUsageTestError.self) {
            try await indexer.index(maximumBytes: 1_024 * 1_024)
        }
        #expect(store.savedCheckpointCount == 0)
    }

    @Test func openCodeBackfillsNewestFirstThenIndexesInsertsAndUpdates() async throws {
        let home = try Self.temporaryDirectory()
        let dataHome = home.appendingPathComponent("xdg", isDirectory: true)
        let databaseDirectory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        let database = databaseDirectory.appendingPathComponent("opencode.db")
        try Self.createIncrementalOpenCodeDatabase(at: database)
        let indexer = BlogUsageSourceIndexer(
            parser: BlogUsageSourceParser(
                homeDirectory: home,
                environment: ["XDG_DATA_HOME": dataHome.path]
            ),
            databaseURL: home.appendingPathComponent("index.sqlite")
        )

        let newestOnly = try await indexer.index(maximumBytes: 4)
        #expect(newestOnly.recordsProcessed == 1)
        #expect(newestOnly.isBackfillInProgress)
        #expect(try await indexer.rows().first?.inputTokens == 30)

        _ = try await indexer.index(maximumBytes: 1_024 * 1_024)
        #expect(try await indexer.rows().first?.inputTokens == 60)

        try Self.updateIncrementalOpenCodeDatabase(at: database)
        let changed = try await indexer.index(maximumBytes: 1_024 * 1_024)
        let row = try #require(try await indexer.rows().first)
        #expect(changed.changedRecords == 2)
        #expect(row.inputTokens == 100)
        #expect(row.messages == 4)
    }

    @Test func serviceRetriesCachedRowsSkipsUnchangedUploadsAndSnapshotsNewEndpoints() async throws {
        let defaults = try #require(UserDefaults(suiteName: "BlogUsageSyncTests-\(UUID().uuidString)"))
        let indexer = ControlledBlogUsageIndexer(revision: 1, rows: [Self.minimalRow()])
        let posting = CountingPosting()
        let keychainAccount = "BlogUsageSyncTests-\(UUID().uuidString)"
        let service = BlogUsageSyncService(
            indexer: indexer,
            client: posting,
            defaults: defaults,
            keychainAccount: keychainAccount,
            oauthProvider: nil
        )
        defer { KeychainHelper.deleteString(account: keychainAccount) }
        await service.setEnabled(true)
        await service.setEndpointURLString("https://example.com/api/usage/ingest")
        await service.setToken("test-token")
        await posting.setError(BlogUsageSyncError.unauthorized)

        #expect(await service.syncNow().state == .failed)
        #expect(await indexer.rowsCallCount == 1)
        await posting.setError(nil)
        #expect(await service.syncNow().state == .success)
        #expect(await indexer.rowsCallCount == 2)
        #expect(await posting.callCount == 2)

        #expect(await service.syncNow().state == .success)
        #expect(await indexer.rowsCallCount == 2)
        #expect(await posting.callCount == 2)

        await service.setEndpointURLString("https://other.example.com/api/usage/ingest")
        #expect(await service.syncNow().state == .success)
        #expect(await indexer.rowsCallCount == 3)
        #expect(await posting.callCount == 3)
    }

    @Test func concurrentSyncRequestsShareOneIndexingTask() async throws {
        let defaults = try #require(UserDefaults(suiteName: "BlogUsageSyncTests-\(UUID().uuidString)"))
        let indexer = ControlledBlogUsageIndexer(
            revision: 1,
            rows: [Self.minimalRow()],
            delayNanoseconds: 100_000_000
        )
        let posting = CountingPosting()
        let keychainAccount = "BlogUsageSyncTests-\(UUID().uuidString)"
        let service = BlogUsageSyncService(
            indexer: indexer,
            client: posting,
            defaults: defaults,
            keychainAccount: keychainAccount,
            oauthProvider: nil
        )
        defer { KeychainHelper.deleteString(account: keychainAccount) }
        await service.setEnabled(true)
        await service.setEndpointURLString("https://example.com/api/usage/ingest")
        await service.setToken("test-token")

        async let first = service.syncNow()
        async let second = service.syncNow()
        let statuses = await [first, second]

        #expect(statuses.allSatisfy { $0.state == .success })
        #expect(await indexer.indexCallCount == 1)
        #expect(await posting.callCount == 1)
    }

    @Test func serviceUsesPassiveAndManualIndexingBudgets() async throws {
        let defaults = try #require(UserDefaults(suiteName: "BlogUsageSyncTests-\(UUID().uuidString)"))
        let indexer = ControlledBlogUsageIndexer(revision: 1, rows: [Self.minimalRow()])
        let keychainAccount = "BlogUsageSyncTests-\(UUID().uuidString)"
        let service = BlogUsageSyncService(
            indexer: indexer,
            client: CountingPosting(),
            defaults: defaults,
            keychainAccount: keychainAccount,
            oauthProvider: nil
        )
        defer { KeychainHelper.deleteString(account: keychainAccount) }
        await service.setEnabled(true)
        await service.setEndpointURLString("https://example.com/api/usage/ingest")
        await service.setToken("test-token")

        _ = await service.syncIfNeeded()
        _ = await service.syncNow()

        #expect(await indexer.requestedBudgets == [
            BlogUsageSourceIndexer.passiveByteBudget,
            BlogUsageSourceIndexer.manualByteBudget
        ])
    }

    private static func requestBodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                throw BlogUsageTestError.requestBodyReadFailed
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func minimalRow() -> BlogUsageIngestRow {
        BlogUsageIngestRow(
            date: "2026-06-02",
            agent: "claude",
            provider: "anthropic",
            model: "claude-sonnet-4-5",
            inputTokens: 1,
            outputTokens: 1,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            reasoningTokens: 0,
            totalTokens: 2,
            costUsd: nil,
            messages: 1
        )
    }

    private static func claudeLine(id: String, inputTokens: Int, padding: String = "") -> String {
        let paddingField = padding.isEmpty ? "" : ",\"padding\":\"\(padding)\""
        return """
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-\(id)"\(paddingField),"message":{"id":"\(id)","model":"claude-sonnet-4-5","usage":{"input_tokens":\(inputTokens),"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """
    }

    private static func codexModelLine(model: String) -> String {
        #"{"timestamp":"2026-06-02T10:00:00Z","payload":{"model":"\#(model)"}}"#
    }

    private static func codexUsageLine(id: String, inputTokens: Int) -> String {
        #"{"timestamp":"2026-06-02T10:01:00Z","payload":{"type":"token_count","id":"\#(id)","info":{"last_token_usage":{"input_tokens":\#(inputTokens),"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}}}"#
    }

    private static func append(_ string: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(string.utf8))
    }

    private static func createOpenCodeDatabase(at url: URL, providerID: String = "opencode-go") throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw BlogUsageTestError.sqliteOpenFailed
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "CREATE TABLE message (id TEXT PRIMARY KEY, createdAt TEXT NOT NULL, data TEXT NOT NULL)", nil, nil, nil) == SQLITE_OK else {
            throw BlogUsageTestError.sqliteExecFailed
        }
        let data = """
        {"role":"assistant","time":{"created":1771952413521},"providerID":"\(providerID)","modelID":"gpt-5.5","tokens":{"input":100,"output":50,"reasoning":10,"cache":{"read":30,"write":20}}}
        """
        let escaped = data.replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(database, "INSERT INTO message (id, createdAt, data) VALUES ('msg-1', '2026-06-02T10:00:00Z', '\(escaped)')", nil, nil, nil) == SQLITE_OK else {
            throw BlogUsageTestError.sqliteExecFailed
        }
    }

    private static func createIncrementalOpenCodeDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw BlogUsageTestError.sqliteOpenFailed
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE message (id TEXT PRIMARY KEY, time_updated INTEGER NOT NULL, data TEXT NOT NULL)",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw BlogUsageTestError.sqliteExecFailed
        }
        for (id, updated, tokens) in [("old", 1, 10), ("middle", 2, 20), ("new", 3, 30)] {
            try insertOpenCodeMessage(id: id, updated: updated, inputTokens: tokens, database: database)
        }
    }

    private static func updateIncrementalOpenCodeDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw BlogUsageTestError.sqliteOpenFailed
        }
        defer { sqlite3_close(database) }
        try insertOpenCodeMessage(id: "inserted", updated: 4, inputTokens: 15, database: database)
        let data = openCodeData(id: "new", inputTokens: 55).replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(
            database,
            "UPDATE message SET time_updated = 5, data = '\(data)' WHERE id = 'new'",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw BlogUsageTestError.sqliteExecFailed
        }
    }

    private static func insertOpenCodeMessage(
        id: String,
        updated: Int,
        inputTokens: Int,
        database: OpaquePointer
    ) throws {
        let data = openCodeData(id: id, inputTokens: inputTokens).replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(
            database,
            "INSERT INTO message (id, time_updated, data) VALUES ('\(id)', \(updated), '\(data)')",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw BlogUsageTestError.sqliteExecFailed
        }
    }

    private static func openCodeData(id: String, inputTokens: Int) -> String {
        #"{"id":"\#(id)","role":"assistant","time":{"created":1771952413521},"providerID":"opencode-go","modelID":"gpt-5.5","tokens":{"input":\#(inputTokens),"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}"#
    }
}

private enum BlogUsageTestError: Error {
    case sqliteOpenFailed
    case sqliteExecFailed
    case requestBodyReadFailed
    case persistenceFailed
}

private final class MutableTestClock: @unchecked Sendable {
    private var date: Date

    init(date: Date) {
        self.date = date
    }

    func now() -> Date {
        date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

private final class BlogUsageURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor CountingPosting: BlogUsageSyncPosting {
    private(set) var callCount = 0
    private var error: Error?

    func setError(_ error: Error?) {
        self.error = error
    }

    func post(rows: [BlogUsageIngestRow], endpoint: URL, token: String) async throws {
        callCount += 1
        if let error {
            throw error
        }
    }
}

private actor ControlledBlogUsageIndexer: BlogUsageIndexing {
    private let currentRevision: Int64
    private let cachedRows: [BlogUsageIngestRow]
    private let delayNanoseconds: UInt64
    private var uploadedRevisions: [String: Int64] = [:]
    private(set) var indexCallCount = 0
    private(set) var rowsCallCount = 0
    private(set) var requestedBudgets: [Int] = []

    init(
        revision: Int64,
        rows: [BlogUsageIngestRow],
        delayNanoseconds: UInt64 = 0
    ) {
        self.currentRevision = revision
        self.cachedRows = rows
        self.delayNanoseconds = delayNanoseconds
    }

    func index(maximumBytes: Int) async throws -> BlogUsageIndexResult {
        indexCallCount += 1
        requestedBudgets.append(maximumBytes)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return BlogUsageIndexResult(
            bytesRead: 0,
            filesProcessed: 0,
            filesSkipped: 0,
            recordsProcessed: 0,
            changedRecords: 0,
            cacheRows: cachedRows.count,
            maximumBufferedBytes: 0,
            remainingSources: 0
        )
    }

    func rows() async throws -> [BlogUsageIngestRow] {
        rowsCallCount += 1
        return cachedRows
    }

    func revision() async throws -> Int64 {
        currentRevision
    }

    func uploadedRevision(endpoint: String) async throws -> Int64 {
        uploadedRevisions[endpoint] ?? -1
    }

    func markUploaded(revision: Int64, endpoint: String) async throws {
        uploadedRevisions[endpoint] = revision
    }
}

private final class FailingBlogUsageIndexStore: BlogUsageIndexStoring, @unchecked Sendable {
    private(set) var savedCheckpointCount = 0

    func withTransaction(_ body: () throws -> Void) throws {
        try body()
    }

    func checkpoint(path: String) throws -> BlogUsageFileCheckpoint? { nil }
    func checkpoints() throws -> [BlogUsageFileCheckpoint] { [] }

    func saveCheckpoint(_ checkpoint: BlogUsageFileCheckpoint) throws {
        savedCheckpointCount += 1
    }

    func rebindFile(from oldPath: String, to newPath: String) throws {}

    func replaceRecord(
        source: BlogUsageIndexedSource,
        container: String,
        recordKey: String,
        dedupeKey: String?,
        event: BlogUsageEvent
    ) throws -> Bool {
        throw BlogUsageTestError.persistenceFailed
    }

    func deleteRecord(source: BlogUsageIndexedSource, container: String, recordKey: String) throws -> Bool { false }
    func deleteRecords(source: BlogUsageIndexedSource, container: String) throws -> Bool { false }
    func aggregateRows() throws -> [BlogUsageIngestRow] { [] }
    func recordCount() throws -> Int { 0 }
    func revision() throws -> Int64 { 0 }
    func advanceRevision() throws -> Int64 { 0 }
    func uploadedRevision(endpointKey: String) throws -> Int64 { -1 }
    func markUploaded(revision: Int64, endpointKey: String) throws {}
    func stringMetadata(forKey key: String) throws -> String? { nil }
    func setMetadata(_ value: String, forKey key: String) throws {}
}
#endif
