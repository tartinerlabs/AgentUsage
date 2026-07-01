//
//  CodexUsageServiceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import Testing
@testable import ClaudeMeter
@testable import ClaudeMeterKit

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

    @Test func decodesSparkWindowsFromAdditionalRateLimits() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sparkReset = now.addingTimeInterval(3600).timeIntervalSince1970
        let sparkWeeklyReset = now.addingTimeInterval(604_800).timeIntervalSince1970
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"spark","rate_limit":{"primary_window":{"used_percent":41,"reset_at":\(Int(sparkReset)),"limit_window_seconds":300},"secondary_window":{"used_percent":52,"reset_at":\(Int(sparkWeeklyReset)),"limit_window_seconds":10080}}}]}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        // primary + weekly + spark 5h + spark weekly
        #expect(snapshot?.windows.count == 4)
        let spark = try #require(snapshot?.windows.first { $0.windowType == .codexSpark })
        let sparkWeekly = try #require(snapshot?.windows.first { $0.windowType == .codexSparkWeekly })
        #expect(spark.utilization == 41)
        #expect(spark.resetsAt == Date(timeIntervalSince1970: sparkReset))
        #expect(spark.name == "Codex Spark")
        #expect(sparkWeekly.utilization == 52)
        #expect(sparkWeekly.name == "Codex Spark weekly")
    }

    @Test func ignoresNonSparkAdditionalRateLimitButStillSurfacesIt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}},"additional_rate_limits":[{"limit_name":"Some Other Limit","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 30))}}}]}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        // primary + weekly + the non-spark primary (no secondary window in the entry)
        #expect(snapshot?.windows.count == 3)
        let extra = try #require(snapshot?.windows.first { $0.windowType == .codexSpark })
        #expect(extra.utilization == 5)
        #expect(extra.name == "Some Other Limit")
    }

    @Test func decodesCreditsBalanceAsCreditsRemaining() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}},"credits":{"has_credits":true,"unlimited":false,"balance":12.34}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.creditsRemaining == 12.34)
    }

    @Test func decodesCreditsBalanceGivenAsString() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}},"credits":{"has_credits":true,"unlimited":false,"balance":"5.50"}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.creditsRemaining == 5.50)
    }

    @Test func planTypeSnakeCaseIsTitleCased() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"free_workspace","rate_limit":{"primary_window":{"used_percent":1,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":2,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.planName == "Free Workspace")
    }

    // MARK: - Helpers

    private final class CallCounter {
        var usageCalls = 0
        var refreshCalls = 0
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
        HTTPURLResponse(
            url: Constants.codexUsageURL,
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
