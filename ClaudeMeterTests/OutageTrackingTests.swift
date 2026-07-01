//
//  OutageTrackingTests.swift
//  ClaudeMeterTests
//
//  Tests for Claude API outage detection, incident lifecycle, and regression safety
//

import Testing
import Foundation
@testable import ClaudeMeter
@testable import ClaudeMeterKit

// MARK: - Outage Classification Tests

@Suite("Outage Error Classification")
struct OutageClassificationTests {

    @Test func serviceUnavailableIsOutage() {
        let error = ClaudeAPIService.APIError.serviceUnavailable
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError500IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(500)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError502IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(502)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError503IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(503)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError400IsNotOutage() {
        let error = ClaudeAPIService.APIError.serverError(400)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func serverError404IsNotOutage() {
        let error = ClaudeAPIService.APIError.serverError(404)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func networkErrorIsNotOutage() {
        let error = ClaudeAPIService.APIError.networkError(URLError(.notConnectedToInternet))
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func rateLimitedIsNotOutage() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: 30)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func unauthorizedIsNotOutage() {
        let error = ClaudeAPIService.APIError.unauthorized
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func invalidResponseIsNotOutage() {
        let error = ClaudeAPIService.APIError.invalidResponse
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func maxRetriesExceededIsNotOutage() {
        let error = ClaudeAPIService.APIError.maxRetriesExceeded
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func nonAPIErrorIsNotOutage() {
        let error = URLError(.timedOut)
        #expect(UsageViewModel.isOutageError(error) == false)
    }
}

// MARK: - Incident Lifecycle Tests

@Suite("Outage Incident Lifecycle")
struct OutageIncidentLifecycleTests {

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600), windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(86400), windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    @Test @MainActor func noIncidentInitially() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func firstOutageCreatesIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident != nil)
        #expect(viewModel.isClaudeServiceDown == true)
        #expect(viewModel.activeClaudeIncident?.lastErrorCode == 503)
    }

    @Test @MainActor func repeatedOutageKeepsStartedAtAndUpdatesLastFailure() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // First outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        let startedAt = viewModel.activeClaudeIncident?.startedAt
        #expect(startedAt != nil)

        // Wait briefly so timestamps differ
        try? await Task.sleep(for: .milliseconds(50))

        // Second outage with different error
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(502))
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident?.startedAt == startedAt)
        #expect(viewModel.activeClaudeIncident?.lastErrorCode == 502)
    }

    @Test @MainActor func successfulFetchClearsIncident() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // Create an outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        #expect(viewModel.isClaudeServiceDown == true)

        // Successful fetch
        await mockAPI.setMockError(nil)
        await mockAPI.setMockSnapshot(makeSnapshot())
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func nonOutageErrorDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.rateLimited(retryAfter: 30))

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func unauthorizedDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.unauthorized)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
    }

    @Test @MainActor func clientServerErrorDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(404))

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
    }
}

// MARK: - Regression Tests

@Suite("Outage Tracking Regressions")
struct OutageRegressionTests {

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600), windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(86400), windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    @Test @MainActor func errorMessageStillSetOnOutage() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        // errorMessage should still be set (existing behavior preserved)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func cachedDataStillUsedOnOutage() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // First, load valid data
        let snapshot = makeSnapshot()
        await mockAPI.setMockSnapshot(snapshot)
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isUsingCachedData == false)

        // Now simulate outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(500))
        await mockAPI.setMockSnapshot(nil)
        await viewModel.refresh(force: true)

        // Should use cached data AND track outage
        #expect(viewModel.isUsingCachedData == true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isClaudeServiceDown == true)
    }

    @Test @MainActor func nonOutageErrorDoesNotAffectExistingIncident() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // Create an outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        let incident = viewModel.activeClaudeIncident
        #expect(incident != nil)

        // Non-outage error should not clear the incident
        await mockAPI.setMockError(ClaudeAPIService.APIError.rateLimited(retryAfter: 10))
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident?.startedAt == incident?.startedAt)
    }
}

// MARK: - Codex Outage Classification

#if os(macOS)
@Suite("Codex Outage Error Classification")
struct CodexOutageClassificationTests {
    @Test func codexServiceUnavailableIsOutage() {
        #expect(UsageViewModel.outageErrorCode(CodexUsageService.CodexError.serviceUnavailable) == 503)
    }

    @Test func codexServerError500IsOutage() {
        #expect(UsageViewModel.outageErrorCode(CodexUsageService.CodexError.serverError(500)) == 500)
    }

    @Test func codexServerError502IsOutage() {
        #expect(UsageViewModel.outageErrorCode(CodexUsageService.CodexError.serverError(502)) == 502)
    }

    @Test func codexServerError404IsNotOutage() {
        #expect(UsageViewModel.outageErrorCode(CodexUsageService.CodexError.serverError(404)) == nil)
    }

    @Test func codexUnauthorizedIsNotOutage() {
        #expect(UsageViewModel.isOutageError(CodexUsageService.CodexError.unauthorized) == false)
    }

    @Test func codexSessionExpiredIsNotOutage() {
        #expect(UsageViewModel.isOutageError(CodexUsageService.CodexError.sessionExpired) == false)
    }

    @Test func codexNetworkErrorIsNotOutage() {
        #expect(UsageViewModel.isOutageError(CodexUsageService.CodexError.networkError(URLError(.timedOut))) == false)
    }

    @Test func codexInvalidResponseIsNotOutage() {
        #expect(UsageViewModel.isOutageError(CodexUsageService.CodexError.invalidResponse) == false)
    }

    @Test func codexMaxRetriesIsNotOutage() {
        #expect(UsageViewModel.isOutageError(CodexUsageService.CodexError.maxRetriesExceeded) == false)
    }
}

// MARK: - OpenCode Outage Classification

@Suite("OpenCode Outage Error Classification")
struct OpenCodeOutageClassificationTests {
    @Test func openCodeServerError503IsOutage() {
        #expect(UsageViewModel.outageErrorCode(OpenCodeGoUsageService.OpenCodeError.serverError(503)) == 503)
    }

    @Test func openCodeServerError502IsOutage() {
        #expect(UsageViewModel.outageErrorCode(OpenCodeGoUsageService.OpenCodeError.serverError(502)) == 502)
    }

    @Test func openCodeServerError404IsNotOutage() {
        #expect(UsageViewModel.outageErrorCode(OpenCodeGoUsageService.OpenCodeError.serverError(404)) == nil)
    }

    @Test func openCodeApiError500IsOutage() {
        #expect(UsageViewModel.outageErrorCode(OpenCodeGoUsageService.OpenCodeError.apiError(500, "boom")) == 500)
    }

    @Test func openCodeApiError404IsNotOutage() {
        #expect(UsageViewModel.outageErrorCode(OpenCodeGoUsageService.OpenCodeError.apiError(404, "nope")) == nil)
    }

    @Test func openCodeInvalidCredentialsIsNotOutage() {
        #expect(UsageViewModel.isOutageError(OpenCodeGoUsageService.OpenCodeError.invalidCredentials) == false)
    }

    @Test func openCodeParseFailedIsNotOutage() {
        #expect(UsageViewModel.isOutageError(OpenCodeGoUsageService.OpenCodeError.parseFailed("x")) == false)
    }

    @Test func openCodeNetworkErrorIsNotOutage() {
        #expect(UsageViewModel.isOutageError(OpenCodeGoUsageService.OpenCodeError.networkError("x")) == false)
    }
}

// MARK: - Codex Outage Lifecycle

@Suite("Codex Outage Lifecycle", .serialized)
struct CodexOutageLifecycleTests {
    @Test @MainActor func outagePreservesCachedCodexSnapshot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let okBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}}}
        """
        let authURL = try Self.writeCodexAuthFile()
        var calls = 0
        let session = Self.codexSession { _ in
            calls += 1
            return calls == 1
                ? (Self.codexResponse(200), Data(okBody.utf8))
                : (Self.codexResponse(503), Data())
        }
        let codexService = CodexUsageService(session: session, authFileURLs: [authURL], now: { now })
        let viewModel = Self.makeViewModel(codexUsageService: codexService)

        // First call succeeds -> snapshot cached, no incident.
        await viewModel.refresh(force: true)
        #expect(viewModel.codexUsage != nil)
        #expect(viewModel.isServiceDown(.codex) == false)

        // Second call 503 -> outage recorded, cached codexUsage preserved.
        await viewModel.refresh(force: true)
        #expect(viewModel.isServiceDown(.codex) == true)
        #expect(viewModel.activeIncident(for: .codex)?.lastErrorCode == 503)
        #expect(viewModel.codexUsage != nil)  // preserved
    }

    @Test @MainActor func successfulFetchClearsCodexIncident() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let okBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":{"used_percent":7,"reset_at":\(Int(now.timeIntervalSince1970 + 600))}}}
        """
        let authURL = try Self.writeCodexAuthFile()
        var calls = 0
        // The Codex service retries 5xx up to 3x per fetchSnapshot(), so the
        // first refresh must exhaust those retries (3 × 503) to register an
        // outage; the second refresh then returns 200 and clears it.
        let session = Self.codexSession { _ in
            calls += 1
            return calls <= 3
                ? (Self.codexResponse(503), Data())
                : (Self.codexResponse(200), Data(okBody.utf8))
        }
        let codexService = CodexUsageService(session: session, authFileURLs: [authURL], now: { now })
        let viewModel = Self.makeViewModel(codexUsageService: codexService)

        await viewModel.refresh(force: true)
        #expect(viewModel.isServiceDown(.codex) == true)

        await viewModel.refresh(force: true)
        #expect(viewModel.isServiceDown(.codex) == false)
        #expect(viewModel.codexUsage != nil)
    }

    @MainActor
    private static func makeViewModel(codexUsageService: CodexUsageService) -> UsageViewModel {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        return UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            codexUsageService: codexUsageService
        )
    }

    private static func codexSession(
        _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CodexOutageURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOutageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func codexResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: Constants.codexUsageURL,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: nil)!
    }

    private static func writeCodexAuthFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexOutageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("auth.json")
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"test-access","refresh_token":"test-refresh","account_id":"test-account"}}
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - OpenCode Outage Lifecycle

@Suite("OpenCode Outage Lifecycle", .serialized)
struct OpenCodeOutageLifecycleTests {
    @Test @MainActor func outagePreservesCachedOpenCodeSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = #"{"rollingUsage":{"usagePercent":12.5,"resetInSec":3600},"weeklyUsage":{"usagePercent":34,"resetInSec":604800}}"#
        var calls = 0
        let transport = OutageMockTransport { _ in
            calls += 1
            if calls == 1 {
                return OutageMockTransport.makeResponse(body: json, status: 200)
            }
            return OutageMockTransport.makeResponse(body: "", status: 503)
        }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { OpenCodeGoUsageService.DashboardConfig(workspaceID: "wrk_TEST", authCookie: "c") },
            now: { now }
        )
        let viewModel = Self.makeViewModel(openCodeGoUsageService: service)

        await viewModel.refresh(force: true)
        #expect(viewModel.openCodeGoUsage != nil)
        #expect(viewModel.isServiceDown(.openCode) == false)

        await viewModel.refresh(force: true)
        #expect(viewModel.isServiceDown(.openCode) == true)
        #expect(viewModel.activeIncident(for: .openCode)?.lastErrorCode == 503)
        #expect(viewModel.openCodeGoUsage != nil)  // preserved
    }

    @Test @MainActor func invalidCredentialsDoesNotCreateIncident() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = OutageMockTransport { _ in
            OutageMockTransport.makeResponse(body: "", status: 401)
        }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { OpenCodeGoUsageService.DashboardConfig(workspaceID: "wrk_TEST", authCookie: "c") },
            now: { now }
        )
        let viewModel = Self.makeViewModel(openCodeGoUsageService: service)

        await viewModel.refresh(force: true)
        // 401 -> invalidCredentials, NOT an outage; column hidden, no incident.
        #expect(viewModel.isServiceDown(.openCode) == false)
        #expect(viewModel.openCodeGoUsage == nil)
    }

    @MainActor
    private static func makeViewModel(openCodeGoUsageService: OpenCodeGoUsageService) -> UsageViewModel {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        return UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            openCodeGoUsageService: openCodeGoUsageService
        )
    }
}

private struct OutageMockTransport: OpenCodeHTTPTransport {
    let handler: @Sendable (URLRequest) -> (Data, HTTPURLResponse)

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        handler(request)
    }

    static func makeResponse(body: String, status: Int) -> (Data, HTTPURLResponse) {
        let url = URL(string: "https://opencode.ai/_server")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private final class CodexOutageURLProtocol: URLProtocol, @unchecked Sendable {
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
