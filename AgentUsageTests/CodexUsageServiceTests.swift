//
//  CodexUsageServiceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("Codex Usage Service", .serialized)
struct CodexUsageServiceTests {
    private static let usageHost = "chatgpt.com"
    private static let refreshHost = "auth.openai.com"

    @Test func bodyWindowsAreMappedFromRateLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primaryReset = now.addingTimeInterval(8535).timeIntervalSince1970
        let weeklyReset = now.addingTimeInterval(323_863).timeIntervalSince1970
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":22,"reset_at":\(Int(primaryReset))},"secondary_window":{"used_percent":34,"reset_at":\(Int(weeklyReset))}}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.provider == .codex)
        #expect(snapshot?.fetchedAt == now)
        #expect(snapshot?.planName == "Pro 5x")
        #expect(snapshot?.windows.count == 2)
        let primary = try #require(snapshot?.windows.first { $0.windowType == .codexFiveHour })
        let weekly = try #require(snapshot?.windows.first { $0.windowType == .codexWeekly })
        #expect(primary.utilization == 22)
        #expect(weekly.utilization == 34)
        #expect(primary.resetsAt == Date(timeIntervalSince1970: primaryReset))
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: weeklyReset))
    }

    @Test func headerPercentsOverrideBody() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}}}
        """
        let headers = [
            "x-codex-primary-used-percent": "77",
            "x-codex-secondary-used-percent": "88",
        ]

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200, headers: headers), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.utilization == 77)
        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.utilization == 88)
        #expect(snapshot?.planName == "Pro 20x")
    }

    @Test func resetAfterSecondsIsResolvedRelativeToFetchTime() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"reset_after_seconds":90},"secondary_window":null}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.count == 1)
        let window = try #require(snapshot?.windows.first)
        #expect(window.windowType == .codexFiveHour)
        #expect(window.utilization == 12)
        #expect(window.resetsAt == now.addingTimeInterval(90))
        #expect(snapshot?.planName == "Plus")
    }

    @Test func unauthorizedRefreshesTokenThenSucceeds() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null}}
        """
        let counter = CallCounter()

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 404), Data())
            }
            let host = request.url?.host ?? ""
            if host == Self.refreshHost {
                counter.refreshCalls += 1
                return (Self.response(200), Data(#"{"access_token":"new-token"}"#.utf8))
            }
            counter.usageCalls += 1
            // First usage call is unauthorized; after refresh it succeeds.
            if counter.usageCalls == 1 {
                return (Self.response(401), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(counter.usageCalls == 2)
        #expect(counter.refreshCalls == 1)
        #expect(snapshot?.windows.first?.utilization == 5)
    }

    @Test func sessionExpiredReturnsNilWithoutFabricatingZero() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = try Self.makeService(now: now) { request in
            let host = request.url?.host ?? ""
            if host == Self.refreshHost {
                return (Self.response(400), Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8))
            }
            return (Self.response(401), Data())
        }
        let snapshot = try await service.fetchSnapshot()

        // Critical anti-bug contract: no snapshot at all, never a 0% window.
        #expect(snapshot == nil)
    }

    @Test func missingAuthFileReturnsNil() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("auth.json")
        let service = CodexUsageService(
            session: Self.mockSession { _ in
                Issue.record("Network must not be hit when no auth file is present")
                return (Self.response(500), Data())
            },
            authFileURLs: [missing],
            now: { now }
        )
        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot == nil)
    }

    // MARK: - Reset Credits

    @Test func resetCreditsCountParsedFromUsageBody() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 404), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 3)
        #expect(credits.expirations.isEmpty)
    }

    @Test func resetCreditsDetailsEnrichExpirations() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":22,"reset_at":\(Int(now.timeIntervalSince1970 + 3600))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":2}}
        """
        let expiry1 = now.addingTimeInterval(3 * 86400)
        let expiry2 = now.addingTimeInterval(7 * 86400)
        let resetBody = """
        {"available_count":2,"credits":[{"status":"available","expires_at":"\(Self.iso8601(expiry2))"},{"status":"available","expires_at":"\(Self.iso8601(expiry1))"}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 2)
        #expect(credits.expirations.count == 2)
        #expect(credits.expirations == [expiry1, expiry2].sorted())
    }

    @Test func resetCreditsDetailsFailureFallsBackToCount() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 500), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 3)
        #expect(credits.expirations.isEmpty)
    }

    @Test func resetCreditsDetailsSendsExpectedHeaders() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":1}}
        """
        let capture = HeaderCapture()

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                capture.openAIBeta = request.value(forHTTPHeaderField: "OpenAI-Beta")
                capture.originator = request.value(forHTTPHeaderField: "originator")
                capture.authorization = request.value(forHTTPHeaderField: "Authorization")
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(#"{"available_count":1,"credits":[]}"#.utf8))
            }
            return (Self.response(200), Data(body.utf8))
        }
        _ = try await service.fetchSnapshot()

        #expect(capture.openAIBeta == "codex-1")
        #expect(capture.originator == "Codex Desktop")
        #expect(capture.authorization == "Bearer test-access")
    }

    @Test func resetCreditsFiltersNonAvailableCredits() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """
        let availableExpiry = now.addingTimeInterval(5 * 86400)
        let resetBody = """
        {"available_count":3,"credits":[{"status":"available","expires_at":"\(Self.iso8601(availableExpiry))"},{"status":"consumed","expires_at":"\(Self.iso8601(now.addingTimeInterval(86400)))"},{"status":"expired","expires_at":"\(Self.iso8601(now.addingTimeInterval(86400)))"},{"status":"available","expires_at":"\(Self.iso8601(now.addingTimeInterval(10 * 86400)))"}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.expirations.count == 2)
        #expect(credits.expirations == [availableExpiry, now.addingTimeInterval(10 * 86400)].sorted())
    }

    @Test func resetCreditsParsesEpochExpiresAt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":1}}
        """
        let epochExpiry = now.addingTimeInterval(6 * 86400).timeIntervalSince1970
        let resetBody = """
        {"available_count":1,"credits":[{"status":"available","expires_at":\(epochExpiry)}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.expirations.count == 1)
        #expect(credits.expirations.first == Date(timeIntervalSince1970: epochExpiry))
    }

    // MARK: - Helpers

    private final class CallCounter {
        var usageCalls = 0
        var refreshCalls = 0
    }

    private final class HeaderCapture {
        var openAIBeta: String?
        var originator: String?
        var authorization: String?
    }

    private static func isResetCreditsPath(_ request: URLRequest) -> Bool {
        (request.url?.path ?? "").contains("rate-limit-reset-credits")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func makeService(
        now: Date,
        handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) throws -> CodexUsageService {
        let authURL = try writeAuthFile()
        return CodexUsageService(
            session: mockSession(handler),
            authFileURLs: [authURL],
            now: { now }
        )
    }

    private static func mockSession(
        _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CodexURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        Self.response(url: Constants.codexUsageURL, status, headers: headers)
    }

    private static func response(url: URL, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: headers
        )!
    }

    private static func writeAuthFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageServiceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("auth.json")
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"test-access","refresh_token":"test-refresh","account_id":"test-account"}}
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private final class CodexURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
