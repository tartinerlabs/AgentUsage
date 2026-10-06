#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("Google provider integration")
struct GoogleProviderTests {
    private static let quota = #"{"buckets":[{"modelId":"gemini-2.5-flash","remainingFraction":0.75,"resetTime":"2026-10-07T00:00:00Z"}]}"#

    @Test func geminiUsesTightestBucketAndKeepsStableModelIDs() throws {
        let body: [String: Any] = ["buckets": [
            ["modelId": "flash", "remainingFraction": 0.75, "resetTime": "2026-10-07T00:00:00Z"],
            ["modelId": "flash", "remainingFraction": 0.25, "resetTime": "2026-10-08T00:00:00Z"],
            ["modelId": "pro", "remainingFraction": 0.0, "resetTime": "2026-10-07T00:00:00.123Z"],
            ["modelId": "unknown", "resetTime": "2026-10-07T00:00:00Z"],
            ["modelId": "invalid", "remainingFraction": 2.0, "resetTime": "2026-10-07T00:00:00Z"],
        ]]
        let snapshot = try GoogleUsageService.mapQuota(body, provider: .gemini, planName: "Pro", now: .now)
        #expect(snapshot.windows.map(\.windowID.rawValue) == ["gemini.model.flash", "gemini.model.pro"])
        #expect(snapshot.windows.map(\.utilization) == [75, 100])
        #expect(snapshot.windows.first?.resetsAt == GoogleUsageService.parseDate("2026-10-08T00:00:00Z"))
        #expect(snapshot.windows.allSatisfy { $0.totalDuration == 0 })
        #expect(snapshot.planName == "Pro")
    }

    @Test func antigravityKeepsProxiedModelsUnderItsOwnProvider() throws {
        let body: [String: Any] = ["models": [
            "claude-sonnet": ["displayName": "Claude Sonnet", "quotaInfo": ["remainingFraction": 0.5, "resetTime": "2026-10-07T00:00:00Z"]],
            "gemini-flash": ["displayName": "Gemini Flash", "quotaInfo": ["remainingFraction": 1.0, "resetTime": "2026-10-07T00:00:00Z"]],
            "missing": ["displayName": "Missing quota"],
        ]]
        let snapshot = try GoogleUsageService.mapQuota(body, provider: .antigravity, planName: nil, now: .now)
        #expect(snapshot.provider == .antigravity)
        #expect(snapshot.windows.map(\.displayName) == ["Claude Sonnet limit", "Gemini Flash limit"])
        #expect(snapshot.windows.map(\.utilization) == [50, 0])
        #expect(!Provider.antigravity.supports(.tokenCost))
    }

    @Test func missingQuotaDoesNotBecomeZeroUsage() {
        #expect(throws: GoogleUsageService.UsageError.self) {
            try GoogleUsageService.mapQuota(["buckets": [["modelId": "pro"]]], provider: .gemini, planName: nil, now: .now)
        }
    }

    @Test func signedOutDoesNotMakeRequests() async throws {
        let service = GoogleUsageService(provider: .gemini, loadCredentials: { nil }, dataLoader: { _ in
            Issue.record("Signed-out provider made a request")
            throw URLError(.badServerResponse)
        })
        #expect(try await service.fetchSnapshot() == nil)
    }

    @Test func expiredGeminiTokenRequiresCLIToRenewWithoutMakingRequests() async throws {
        let service = GoogleUsageService(
            provider: .gemini,
            loadCredentials: { GoogleUsageCredentials(accessToken: "expired", expiresAt: .distantPast) },
            dataLoader: { _ in
                Issue.record("Expired credentials made a request")
                throw URLError(.badServerResponse)
            }
        )
        await #expect(throws: GoogleUsageService.UsageError.self) {
            try await service.fetchSnapshot()
        }
    }

    @Test func geminiResolvesManagedProjectUsingTheCLIAccessToken() async throws {
        let transport = GoogleFixtureTransport(quota: Self.quota)
        let service = GoogleUsageService(
            provider: .gemini,
            loadCredentials: { GoogleUsageCredentials(accessToken: "local") },
            dataLoader: { try await transport.load($0) }
        )
        #expect(try await service.fetchSnapshot()?.windows.count == 1)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "cloudcode-pa.googleapis.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer local" })
        let quota = try #require(requests.last?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: quota) as? [String: String])
        #expect(body["project"] == "managed-project")
    }

    @Test func antigravityDoesNotRefreshWithGeminiOAuthIdentity() async throws {
        let service = GoogleUsageService(provider: .antigravity, loadCredentials: {
            GoogleUsageCredentials(accessToken: "local")
        }, dataLoader: { request in
            #expect(request.url?.host == "cloudcode-pa.googleapis.com")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (Data(), response)
        })
        await #expect(throws: GoogleUsageService.UsageError.self) { try await service.fetchSnapshot() }
    }

    @Test func antigravityVerifiesFullModelCatalogAllowancesAgainstQuotaBuckets() async throws {
        let catalog = #"{"models":{"gemini-2.5-flash":{"quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-07T00:00:00Z"}}}}"#
        let transport = GoogleFixtureTransport(quota: Self.quota, modelCatalog: catalog)
        let service = GoogleUsageService(
            provider: .antigravity, loadCredentials: { GoogleUsageCredentials(accessToken: "local") },
            dataLoader: { try await transport.load($0) }
        )
        let snapshot = try #require(try await service.fetchSnapshot())
        #expect(snapshot.provider == .antigravity)
        #expect(snapshot.windows.first?.utilization == 25)
        #expect(snapshot.windows.first?.windowID.rawValue == "antigravity.model.gemini-2.5-flash")
        #expect(await transport.requests.count == 4)
        #expect(await transport.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == "antigravity/hub/2.9.1 darwin/arm64"
                || $0.value(forHTTPHeaderField: "User-Agent") == "antigravity/hub/2.9.1 darwin/amd64"
        })
    }

    @Test func antigravityPrefersQuotaSummaryPools() async throws {
        let summary = """
        {"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","remainingFraction":0.3,"resetTime":"2026-10-13T00:00:00Z","window":"weekly"}]},\
        {"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","remainingFraction":1,"resetTime":"2026-10-13T00:00:00Z","window":"weekly"}]}]}
        """
        let transport = GoogleFixtureTransport(quota: Self.quota, summary: summary)
        let service = GoogleUsageService(
            provider: .antigravity, loadCredentials: { GoogleUsageCredentials(accessToken: "local") },
            dataLoader: { try await transport.load($0) }
        )
        let snapshot = try #require(try await service.fetchSnapshot())
        #expect(snapshot.windows.map(\.windowID.rawValue) == ["antigravity.quota.3p-weekly", "antigravity.quota.gemini-weekly"])
        #expect(snapshot.windows.map(\.displayName) == ["Claude and GPT models weekly limit", "Gemini Models weekly limit"])
        #expect(snapshot.windows.map(\.utilization) == [0, 70])
        #expect(snapshot.windows.allSatisfy { $0.totalDuration == 7 * 24 * 3_600 })
        #expect(await transport.requests.map { $0.url?.absoluteString.hasSuffix(":retrieveUserQuotaSummary") } == [false, true])
    }

    @Test func antigravityKeepsModelCatalogWhenQuotaBucketsAreForbidden() async throws {
        let catalog = #"{"models":{"gemini-2.5-flash":{"displayName":"Gemini Flash","quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-07T00:00:00Z"}}}}"#
        let service = GoogleUsageService(
            provider: .antigravity,
            loadCredentials: { GoogleUsageCredentials(accessToken: "local") },
            dataLoader: { request in
                let url = try #require(request.url)
                let path = url.absoluteString
                let status: Int
                let body: String
                if path.hasSuffix(":loadCodeAssist") {
                    status = 200
                    body = #"{"cloudaicompanionProject":"project","paidTier":{"name":"Antigravity"}}"#
                } else if path.hasSuffix(":retrieveUserQuotaSummary") {
                    status = 403
                    body = "{}"
                } else if path.hasSuffix(":fetchAvailableModels") {
                    status = 200
                    body = catalog
                } else {
                    status = 403
                    body = "{}"
                }
                let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
                return (Data(body.utf8), response)
            }
        )
        let snapshot = try #require(try await service.fetchSnapshot())
        #expect(snapshot.planName == "Antigravity")
        #expect(snapshot.windows.map(\.displayName) == ["Gemini Flash limit"])
        #expect(snapshot.windows.first?.utilization == 0)
    }

    @Test func readsAntigravityCLIKeychainSession() throws {
        let json = #"{"token":{"access_token":"ya29.test","expiry":"2026-10-06T22:10:40.66361+08:00"}}"#
        let wrapped = "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
        let credentials = try #require(GoogleUsageAuth.parseAntigravityKeychain(wrapped))
        #expect(credentials.accessToken == "ya29.test")
        #expect(credentials.expiresAt == GoogleUsageService.parseDate("2026-10-06T22:10:40.66361+08:00"))
        #expect(GoogleUsageAuth.parseAntigravityKeychain(#"{"access_token":""}"#) == nil)
    }

    @Test func geminiApiKeyLoginIgnoresOldOAuthCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appendingPathComponent("oauth_creds.json")
        let original = Data(#"{"access_token":"local","refresh_token":"refresh","expiry_date":1800000000000}"#.utf8)
        try original.write(to: auth)
        #expect(GoogleUsageAuth.gemini(at: auth)?.accessToken == "local")
        try Data(#"{"security":{"auth":{"selectedType":"gemini-api-key"}}}"#.utf8)
            .write(to: root.appendingPathComponent("settings.json"))
        #expect(GoogleUsageAuth.gemini(at: auth) == nil)
        #expect(try Data(contentsOf: auth) == original)
    }

    @Test @MainActor func googleErrorsParticipateInCooldownAndOutageTracking() {
        #expect(UsageViewModel.rateLimitCooldown(for: GoogleUsageService.UsageError.rateLimited(60)) == 60)
        #expect(UsageViewModel.outageErrorCode(GoogleUsageService.UsageError.serverError(503)) == 503)
        #expect(!UsageViewModel.isOutageError(GoogleUsageService.UsageError.unauthorized(.gemini)))
    }

    @Test func readsAntigravityUnifiedAndLegacyAuthWithoutModifyingDatabase() throws {
        func field(_ number: UInt8, _ data: Data) -> Data {
            precondition(data.count < 128)
            return Data([number << 3 | 2, UInt8(data.count)]) + data
        }
        let oauth = field(1, Data("test-access-token".utf8))
        let row = field(1, Data(oauth.base64EncodedString().utf8))
        let entry = field(1, Data("oauthTokenInfoSentinelKey".utf8)) + field(2, row)
        let topic = field(1, entry)
        let unified = GoogleUsageAuth.parseAntigravity(topic.base64EncodedString(), key: "antigravityUnifiedStateSync.oauthToken")
        let legacy = GoogleUsageAuth.parseAntigravity(field(6, oauth).base64EncodedString(), key: "jetskiStateSync.agentManagerInitState")
        #expect(unified?.accessToken == "test-access-token")
        #expect(legacy?.accessToken == "test-access-token")
        let malformed = GoogleUsageAuth.parseAntigravity(
            Data([0x0a, 0xff]).base64EncodedString(), key: "antigravityUnifiedStateSync.oauthToken"
        )
        #expect(malformed == nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.vscdb")
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE ItemTable(key TEXT, value TEXT);
            INSERT INTO ItemTable VALUES('antigravityAuthStatus', '{"apiKey":"wal-token"}');
            """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        #expect(GoogleUsageAuth.antigravity(at: [url])?.accessToken == "wal-token")
        #expect(sqlite3_total_changes(database) == 1)
    }
}

private actor GoogleFixtureTransport {
    var requests: [URLRequest] = []
    let quota: String
    let modelCatalog: String?
    let summary: String?
    init(quota: String, modelCatalog: String? = nil, summary: String? = nil) {
        self.quota = quota
        self.modelCatalog = modelCatalog
        self.summary = summary
    }
    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let body: String
        if request.url?.absoluteString.hasSuffix(":loadCodeAssist") == true {
            body = #"{"cloudaicompanionProject":{"id":"managed-project"},"currentTier":{"name":"Pro"}}"#
        } else if request.url?.absoluteString.hasSuffix(":retrieveUserQuotaSummary") == true {
            body = summary ?? #"{"groups":[]}"#
        } else if request.url?.absoluteString.hasSuffix(":fetchAvailableModels") == true {
            body = modelCatalog ?? quota
        } else { body = quota }
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }
}

@Suite("Gemini local usage")
struct GeminiLogSourceTests {
    private static let message = #"{"id":"turn-a","type":"gemini","model":"gemini-2.5-flash","#
        + #""timestamp":"2026-10-06T10:00:00Z","tokens":{"input":1000,"output":100,"cached":400,"thoughts":50}}"#

    @Test(arguments: [
        "gemini-3-pro-preview", "gemini-3.1-pro-preview-customtools", "gemini-3-flash",
        "gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.8-flash",
        "models/gemini-3.8-flash", "gemini/gemini-3.1-flash-lite", "gemini-2.0-flash-001",
    ])
    func recognizesConcreteCliModelsAndProviderPrefixes(_ model: String) {
        #expect(ModelPricing.fallbackRates(forProvider: "gemini", model: model) != nil)
    }

    @Test func unknownModelsAndAmbiguousRoutingAliasesDoNotInventRates() {
        #expect(ModelPricing.fallbackRates(forProvider: "gemini", model: "gemini-future-pro") == nil)
        #expect(ModelPricing.fallbackRates(forProvider: "gemini", model: "auto") == nil)
    }

    @Test func promotionalFlashPricesFollowTheSessionDate() throws {
        let discounted = try #require(ModelPricing.geminiFallbackRates(
            for: "gemini-3.8-flash", at: Date(timeIntervalSince1970: 1_798_761_599)
        ))
        let standard = try #require(ModelPricing.geminiFallbackRates(
            for: "gemini-3.8-flash", at: Date(timeIntervalSince1970: 1_798_761_600)
        ))
        #expect(discounted.inputPerMTok == 0.75)
        #expect(standard.inputPerMTok == 1.50)
        let cost = try #require(ModelPricing.costUSD(
            provider: "gemini", model: "models/gemini-3.8-flash", inputTokens: 1_000_000,
            outputTokens: 1_000_000, cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0,
            pricingDate: Date(timeIntervalSince1970: 1_798_761_599)
        ))
        #expect(cost == 4.50)
    }

    @Test func cachedPromptTokensCountTowardTheProContextPricingThreshold() throws {
        let cost = try #require(ModelPricing.costUSD(
            provider: "gemini", model: "gemini/gemini-3.1-pro-preview", inputTokens: 100_001,
            outputTokens: 0, cacheReadTokens: 100_000, cacheWriteTokens: 0, reasoningTokens: 0
        ))
        #expect(abs(cost - 0.440004) < 0.0000001)
    }

    @Test func separatesCachedInputAndBillsThinkingAsOutput() throws {
        let data = Data((#"{"sessionId":"session","messages":["# + Self.message + "]}").utf8)
        let entry = try #require(GeminiLogSource.parse(data: data, jsonl: false).first)
        #expect(entry.tokens.inputTokens == 600)
        #expect(entry.tokens.cacheReadTokens == 400)
        #expect(entry.tokens.outputTokens == 100)
        #expect(entry.tokens.reasoningTokens == 50)
        #expect(entry.tokens.totalTokens == 1150)
        #expect(entry.pricingProviderKey == "gemini")
        let cost = try #require(ModelPricing.costUSD(
            provider: "gemini", model: "gemini-2.5-flash", inputTokens: 600, outputTokens: 100,
            cacheReadTokens: 400, cacheWriteTokens: 0, reasoningTokens: 50
        ))
        let withoutThinking = try #require(ModelPricing.costUSD(
            provider: "gemini", model: "gemini-2.5-flash", inputTokens: 600, outputTokens: 100,
            cacheReadTokens: 400, cacheWriteTokens: 0, reasoningTokens: 0
        ))
        #expect(cost > withoutThinking)
    }

    @Test func jsonlHandlesMetadataPatchesRepeatedMessagesAndTruncatedLines() throws {
        let log = [#"{"sessionId":"session","projectHash":"project","kind":"subagent"}"#, Self.message, Self.message,
                   #"{"$patch":{"id":"turn-a","tokens":{"input":2000,"output":150}}}"#, "{truncated"].joined(separator: "\n")
        let entries = GeminiLogSource.parse(data: Data(log.utf8), jsonl: true)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.tokens.inputTokens == 2000)
        #expect(entry.isSubagentSession)
        #expect(entry.dedupKey == "gemini:session:turn-a")
    }

    @Test func rewindMatchesGeminiRecordingSemantics() {
        let log = [#"{"sessionId":"session","projectHash":"project"}"#, Self.message, #"{"$rewindTo":"turn-a"}"#].joined(separator: "\n")
        #expect(GeminiLogSource.parse(data: Data(log.utf8), jsonl: true).isEmpty)
    }

    @Test func migratedJsonAndJsonlCopiesAreCountedOnceAndCacheRefreshes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chats = root.appendingPathComponent("project/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let json = Data((#"{"sessionId":"session","messages":["# + Self.message + "]}").utf8)
        try json.write(to: chats.appendingPathComponent("session.json"))
        let jsonlURL = chats.appendingPathComponent("session.jsonl")
        let metadata = #"{"sessionId":"session","projectHash":"project"}"#
        let newerMessage = Self.message.replacingOccurrences(of: "1000", with: "2000")
        try Data((metadata + "\n" + newerMessage).utf8).write(to: jsonlURL)
        let source = GeminiLogSource(directory: root)
        #expect(try await source.fetchEntries(since: .distantPast).count == 1)
        #expect(try await source.fetchEntries(since: .distantPast).first?.tokens.inputTokens == 1600)
        #expect(try await source.fetchEntries(since: .distantFuture).isEmpty)
        try FileManager.default.removeItem(at: chats.appendingPathComponent("session.json"))
        let updatedMessage = Self.message.replacingOccurrences(of: "1000", with: "3000")
        try Data((metadata + "\n" + updatedMessage).utf8).write(to: jsonlURL)
        #expect(try await source.fetchEntries(since: .distantPast).first?.tokens.inputTokens == 2600)
    }
}
#endif
