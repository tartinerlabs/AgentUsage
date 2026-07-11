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
        try """
        {"type":"assistant","timestamp":"2026-06-02T10:00:00Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let defaults = try #require(UserDefaults(suiteName: "BlogUsageSyncTests-\(UUID().uuidString)"))
        let posting = CountingPosting()
        let clock = MutableTestClock(date: Date(timeIntervalSince1970: 1_780_000_000))
        let keychainAccount = "BlogUsageSyncTests-\(UUID().uuidString)"
        let service = BlogUsageSyncService(
            parser: BlogUsageSourceParser(homeDirectory: home, environment: [:]),
            client: posting,
            defaults: defaults,
            keychainAccount: keychainAccount,
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
}

private enum BlogUsageTestError: Error {
    case sqliteOpenFailed
    case sqliteExecFailed
    case requestBodyReadFailed
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
#endif
