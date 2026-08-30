//
//  GrokUsageServiceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("Grok Usage Service", .serialized)
struct GrokUsageServiceTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func weeklyCreditsWindowMapsPercentPlanAndReset() throws {
        let start = "2026-08-25T10:05:19.861909Z"
        let end = "2026-09-01T10:05:19.861909Z"
        let credits: [String: Any] = [
            "subscriptionTier": "SuperGrok",
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": start,
                    "end": end,
                ],
                "creditUsagePercent": 74.0,
            ],
        ]

        let snapshot = try #require(
            GrokUsageService.mapBilling(
                creditsBody: credits,
                fallbackBody: nil,
                now: Self.fixedNow
            )
        )

        #expect(snapshot.provider == .grok)
        #expect(snapshot.planName == "SuperGrok")
        #expect(snapshot.windows.count == 1)
        let weekly = try #require(snapshot.windows.first)
        #expect(weekly.windowType == .grokWeekly)
        #expect(weekly.displayName == "Weekly limit")
        #expect(weekly.utilization == 74)
        #expect(weekly.resetsAt == parseDate(end))
    }

    @Test func omittedWeeklyPercentDefaultsToZero() throws {
        let credits: [String: Any] = [
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": "2026-08-25T10:05:19Z",
                    "end": "2026-09-01T10:05:19Z",
                ],
            ],
        ]

        let snapshot = try #require(
            GrokUsageService.mapBilling(
                creditsBody: credits,
                fallbackBody: nil,
                now: Self.fixedNow
            )
        )
        #expect(snapshot.windows.first?.utilization == 0)
        #expect(snapshot.windows.first?.windowType == .grokWeekly)
    }

    @Test func onDemandCapMapsToExtraUsageInDollars() throws {
        let credits: [String: Any] = [
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "end": "2026-09-01T10:05:19Z",
                ],
                "creditUsagePercent": 10,
                "onDemandCap": ["val": "5000"],
                "onDemandUsed": ["val": "1250"],
            ],
        ]

        let snapshot = try #require(
            GrokUsageService.mapBilling(
                creditsBody: credits,
                fallbackBody: nil,
                now: Self.fixedNow
            )
        )
        #expect(snapshot.extraUsage?.used == 12.5)
        #expect(snapshot.extraUsage?.limit == 50)
        #expect(snapshot.extraUsage?.currencyCode == "USD")
    }

    @Test func monthlyFallbackIsUsedWhenWeeklyPeriodIsAbsent() throws {
        let fallback: [String: Any] = [
            "config": [
                "monthlyLimit": ["val": "20000"],
                "used": ["val": "5000"],
                "billingPeriodEnd": "2026-09-30T00:00:00Z",
                "billingPeriodStart": "2026-09-01T00:00:00Z",
            ],
        ]

        let snapshot = try #require(
            GrokUsageService.mapBilling(
                creditsBody: [:],
                fallbackBody: fallback,
                now: Self.fixedNow
            )
        )
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.windowID.rawValue == "grok.monthly")
        #expect(snapshot.windows.first?.utilization == 25)
    }

    @Test func fetchSnapshotSendsCreditsQueryAndClientHeaders() async throws {
        let capture = HeaderCapture()
        let end = Self.fixedNow.addingTimeInterval(86_400)
        let body = """
        {"subscriptionTier":"SuperGrok","config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"\(iso8601(end))"},"creditUsagePercent":33}}
        """

        let service = try makeService { request in
            if isCreditsRequest(request) {
                capture.authorization = request.value(forHTTPHeaderField: "Authorization")
                capture.surface = request.value(forHTTPHeaderField: Constants.grokClientSurfaceHeader)
                capture.version = request.value(forHTTPHeaderField: Constants.grokClientVersionHeader)
                return (response(url: Constants.grokBillingCreditsURL, 200), Data(body.utf8))
            }
            return (response(url: Constants.grokBillingURL, 200), Data(#"{"config":{}}"#.utf8))
        }

        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot?.windows.first?.utilization == 33)
        #expect(snapshot?.planName == "SuperGrok")
        #expect(capture.authorization == "Bearer test-access")
        #expect(capture.surface == "grok-build")
        #expect(capture.version == "1.0.13")
    }

    @Test func unauthorizedRefreshesOnceThenSucceeds() async throws {
        let counter = CallCounter()
        let end = Self.fixedNow.addingTimeInterval(86_400)
        let body = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"\(iso8601(end))"},"creditUsagePercent":12}}
        """

        let service = try makeService { request in
            if request.url?.host == "auth.x.ai" {
                counter.refreshCalls += 1
                #expect(request.httpMethod == "POST")
                return (
                    response(url: Constants.grokTokenRefreshURL, 200),
                    Data(#"{"access_token":"refreshed-access"}"#.utf8)
                )
            }
            let token = request.value(forHTTPHeaderField: "Authorization")
            if token == "Bearer test-access" {
                counter.usageCalls += 1
                return (response(url: request.url ?? Constants.grokBillingURL, 401), Data())
            }
            #expect(token == "Bearer refreshed-access")
            return (response(url: request.url ?? Constants.grokBillingCreditsURL, 200), Data(body.utf8))
        }

        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot?.windows.first?.utilization == 12)
        #expect(counter.refreshCalls == 1)
        #expect(counter.usageCalls >= 1)
    }

    @Test func missingAuthFileReturnsNil() async throws {
        let service = GrokUsageService(
            session: mockSession { _ in
                Issue.record("Network should not be used without auth")
                return (response(url: Constants.grokBillingURL, 500), Data())
            },
            authFileURLs: [FileManager.default.temporaryDirectory.appendingPathComponent("missing-grok-auth.json")],
            versionFileURLs: [],
            now: { Self.fixedNow }
        )
        #expect(try await service.fetchSnapshot() == nil)
    }

    // MARK: - Helpers

    private final class HeaderCapture: @unchecked Sendable {
        var authorization: String?
        var surface: String?
        var version: String?
    }

    private final class CallCounter: @unchecked Sendable {
        var usageCalls = 0
        var refreshCalls = 0
    }

    private func isCreditsRequest(_ request: URLRequest) -> Bool {
        (request.url?.query ?? "").contains("format=credits")
    }

    private func parseDate(_ raw: String) -> Date? {
        Self.parseDate(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func makeService(
        handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) throws -> GrokUsageService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokUsageServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authURL = directory.appendingPathComponent("auth.json")
        try """
        {"https://auth.x.ai::client":{"key":"test-access","refresh_token":"test-refresh","oidc_client_id":"client","create_time":"2026-01-01T00:00:00Z"}}
        """.write(to: authURL, atomically: true, encoding: .utf8)
        let versionURL = directory.appendingPathComponent("version.json")
        try #"{"version":"1.0.13"}"#.write(to: versionURL, atomically: true, encoding: .utf8)

        return GrokUsageService(
            session: mockSession(handler),
            authFileURLs: [authURL],
            versionFileURLs: [versionURL],
            now: { Self.fixedNow }
        )
    }

    private func mockSession(
        _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        GrokURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)!
    }
}

private final class GrokURLProtocol: URLProtocol {
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
