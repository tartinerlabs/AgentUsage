//
//  OpenCodeGoUsageServiceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import Testing
@testable import ClaudeMeter
import ClaudeMeterKit

@Suite("OpenCode Go Usage Service")
struct OpenCodeGoUsageServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - parseSubscription: JSON primary path

    @Test func parsesJSONUsageWindows() throws {
        let json = #"""
        {"rollingUsage":{"usagePercent":12.5,"resetInSec":3600},
         "weeklyUsage":{"usagePercent":34,"resetInSec":604800},
         "monthlyUsage":{"usagePercent":56.75,"resetInSec":1209600}}
        """#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: json, now: Self.now))

        #expect(snapshot.provider == .openCode)
        #expect(snapshot.planName == "Go")
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows.map(\.windowType) == [.openCodeGoFiveHour, .openCodeGoWeekly, .openCodeGoMonthly])
        #expect(snapshot.windows[0].utilization == 12.5)
        #expect(snapshot.windows[0].resetsAt == Self.now.addingTimeInterval(3600))
        #expect(snapshot.windows[1].utilization == 34)
        #expect(snapshot.windows[1].resetsAt == Self.now.addingTimeInterval(604800))
        #expect(snapshot.windows[2].utilization == 56.75)
        #expect(snapshot.windows[2].resetsAt == Self.now.addingTimeInterval(1209600))
    }

    @Test func parsesJSONWithAliasedKeys() throws {
        // usedPercent / resetInSeconds aliases; percent as a fraction (0.15 -> 15).
        let json = #"""
        {"rollingUsage":{"usedPercent":0.15,"resetInSeconds":3600},
         "weeklyUsage":{"usedPercent":0.50,"resetInSeconds":604800}}
        """#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: json, now: Self.now))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].utilization == 15)
        #expect(snapshot.windows[1].utilization == 50)
    }

    @Test func parsesJSONComputingPercentFromUsedAndLimit() throws {
        let json = #"""
        {"rollingUsage":{"used":30,"limit":200,"resetInSec":3600},
         "weeklyUsage":{"used":10,"limit":100,"resetInSec":604800}}
        """#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: json, now: Self.now))

        // 30/200*100 = 15 ; 10/100*100 = 10
        #expect(snapshot.windows[0].utilization == 15)
        #expect(snapshot.windows[1].utilization == 10)
    }

    @Test func parsesJSONNestedUnderDataKey() throws {
        let json = #"{"data":{"usage":{"rollingUsage":{"usagePercent":20,"resetInSec":3600},"weeklyUsage":{"usagePercent":40,"resetInSec":604800}}}}"#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: json, now: Self.now))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].utilization == 20)
        #expect(snapshot.windows[1].utilization == 40)
    }

    @Test func parsesJSONWithoutMonthly() throws {
        let json = #"{"rollingUsage":{"usagePercent":12.5,"resetInSec":3600},"weeklyUsage":{"usagePercent":34,"resetInSec":604800}}"#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: json, now: Self.now))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows.map(\.windowType) == [.openCodeGoFiveHour, .openCodeGoWeekly])
    }

    // MARK: - parseSubscription: regex fallback

    @Test func parsesRegexFallbackRSCPayload() throws {
        // RSC-style serialization with the $R[n]= prefix; not valid JSON, so the
        // regex fallback path handles it.
        let text = #"""
        rollingUsage:$R[1]={status:"active",usagePercent:12.5,resetInSec:3600}
        weeklyUsage:$R[2]={status:"active",resetInSec:604800,usagePercent:34}
        monthlyUsage:{"status":"active","usagePercent":"56.75","resetInSec":"1209600"}
        """#

        let snapshot = try #require(try OpenCodeGoUsageService.parseSubscription(text: text, now: Self.now))

        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows[0].utilization == 12.5)
        #expect(snapshot.windows[0].resetsAt == Self.now.addingTimeInterval(3600))
        #expect(snapshot.windows[1].utilization == 34)
        #expect(snapshot.windows[2].utilization == 56.75)
    }

    @Test func parseFailsOnMissingUsageFields() throws {
        #expect(throws: OpenCodeGoUsageService.OpenCodeError.self) {
            _ = try OpenCodeGoUsageService.parseSubscription(text: "nothing useful here", now: Self.now)
        }
    }

    @Test func parseFailsOnEmptyString() throws {
        #expect(throws: OpenCodeGoUsageService.OpenCodeError.self) {
            _ = try OpenCodeGoUsageService.parseSubscription(text: "", now: Self.now)
        }
    }

    // MARK: - Config

    @Test func loadsConfigCookieOnlyWithoutWorkspace() throws {
        // Cookie present, no workspace ID -> auto-discovered at fetch time.
        let config = try #require(OpenCodeGoUsageService.DashboardConfig.load(environment: [
            "OPENCODE_GO_AUTH_COOKIE": "secret-cookie"
        ]))

        #expect(config.workspaceID == nil)
        #expect(config.cookieHeader == "auth=secret-cookie")
    }

    @Test func loadsConfigFromEnvironmentAndNormalizesURLWorkspace() throws {
        let config = try #require(OpenCodeGoUsageService.DashboardConfig.load(environment: [
            "OPENCODE_GO_WORKSPACE_ID": "https://opencode.ai/workspace/wrk_01ABCDEF0123456789ABCDEFG/go",
            "OPENCODE_GO_AUTH_COOKIE": "secret-cookie"
        ]))

        #expect(config.workspaceID == "wrk_01ABCDEF0123456789ABCDEFG")
        #expect(config.cookieHeader == "auth=secret-cookie")
        #expect(config.dashboardURL.absoluteString == "https://opencode.ai/workspace/wrk_01ABCDEF0123456789ABCDEFG/go")
    }

    @Test func normalizesWorkspaceIDVariants() {
        let normalize = OpenCodeGoUsageService.DashboardConfig.normalizedWorkspaceID
        #expect(normalize("wrk_01ABCDEF0123456789ABCDEFG") == "wrk_01ABCDEF0123456789ABCDEFG")
        #expect(normalize("https://opencode.ai/workspace/wrk_01ABCDEF0123456789ABCDEFG/go") == "wrk_01ABCDEF0123456789ABCDEFG")
        #expect(normalize("path wrk_ZZZ999 here") == "wrk_ZZZ999")
        #expect(normalize("") == nil)
        #expect(normalize(nil) == nil)
    }

    @Test func cookieHeaderSupportsHostAuthVariant() {
        let config = OpenCodeGoUsageService.DashboardConfig(workspaceID: nil, authCookie: "__Host-auth=abc; path=/; secure")
        #expect(config.cookieHeader == "__Host-auth=abc; path=/; secure")

        let plain = OpenCodeGoUsageService.DashboardConfig(workspaceID: nil, authCookie: "raw-token")
        #expect(plain.cookieHeader == "auth=raw-token")
    }

    // MARK: - Sign-out / redirect

    @Test func detectsSignedOutBody() {
        #expect(OpenCodeGoUsageService.looksSignedOut(text: "please sign in to continue"))
        #expect(OpenCodeGoUsageService.looksSignedOut(text: "Login required"))
        #expect(OpenCodeGoUsageService.looksSignedOut(text: #"actor of type "public""#))
        #expect(OpenCodeGoUsageService.looksSignedOut(text: "not associated with an account"))
        #expect(!OpenCodeGoUsageService.looksSignedOut(text: #"{"rollingUsage":{"usagePercent":12}}"#))
    }

    @Test func blocksCrossHostRedirect() {
        let source = URL(string: "https://opencode.ai/_server")
        let crossHost = URL(string: "https://evil.example.com/steal")
        #expect(!OpenCodeGoUsageService.allowsRedirect(from: source, to: crossHost))
    }

    @Test func allowsSameHostRedirect() {
        let source = URL(string: "https://opencode.ai/_server")
        let sameHost = URL(string: "https://opencode.ai/_server?id=xyz")
        #expect(OpenCodeGoUsageService.allowsRedirect(from: source, to: sameHost))
    }

    @Test func blocksInsecureRedirect() {
        let source = URL(string: "https://opencode.ai/_server")
        let insecure = URL(string: "http://opencode.ai/_server")
        #expect(!OpenCodeGoUsageService.allowsRedirect(from: source, to: insecure))
    }

    // MARK: - Network via mock transport

    @Test func fetchReturnsSnapshotOnJSONResponse() async throws {
        let json = #"{"rollingUsage":{"usagePercent":12.5,"resetInSec":3600},"weeklyUsage":{"usagePercent":34,"resetInSec":604800}}"#
        let transport = MockTransport { _ in
            Self.makeResponse(body: json, status: 200)
        }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        let snapshot = try #require(await service.fetchSnapshot())
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].utilization == 12.5)
    }

    @Test func fetchThrowsInvalidCredentialsOn401() async {
        let transport = MockTransport { _ in Self.makeResponse(body: "", status: 401) }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        await #expect(throws: OpenCodeGoUsageService.OpenCodeError.invalidCredentials) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func fetchThrowsInvalidCredentialsOn403() async {
        let transport = MockTransport { _ in Self.makeResponse(body: "", status: 403) }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        await #expect(throws: OpenCodeGoUsageService.OpenCodeError.invalidCredentials) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func fetchThrowsServerErrorOn503() async {
        let transport = MockTransport { _ in Self.makeResponse(body: "", status: 503) }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        await #expect(throws: OpenCodeGoUsageService.OpenCodeError.serverError(503)) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func fetchThrowsApiErrorOn404() async {
        let transport = MockTransport { _ in Self.makeResponse(body: "not found", status: 404) }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        await #expect(throws: OpenCodeGoUsageService.OpenCodeError.self) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func fetchThrowsInvalidCredentialsOnSignedOutBody() async {
        let transport = MockTransport { _ in
            Self.makeResponse(body: "please sign in to continue", status: 200)
        }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        await #expect(throws: OpenCodeGoUsageService.OpenCodeError.invalidCredentials) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func fetchAutoDiscoversWorkspaceID() async throws {
        // No workspaceID in config -> service must call the workspaces server-fn
        // first, then the subscription server-fn.
        let workspacePayload = #"{"id":"wrk_AUTODISCOVERED123"}"#
        let usageJSON = #"{"rollingUsage":{"usagePercent":42,"resetInSec":3600},"weeklyUsage":{"usagePercent":7,"resetInSec":604800}}"#
        let transport = MockTransport { request in
            let serverID = request.value(forHTTPHeaderField: "X-Server-Id")
            if serverID == OpenCodeGoUsageService.workspacesServerID {
                return Self.makeResponse(body: workspacePayload, status: 200)
            }
            return Self.makeResponse(body: usageJSON, status: 200)
        }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { Self.cookieOnlyConfig },
            now: { Self.now }
        )

        let snapshot = try #require(await service.fetchSnapshot())
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].utilization == 42)
    }

    @Test func fetchReturnsNilWhenNoConfig() async {
        let transport = MockTransport { _ in Self.makeResponse(body: "{}", status: 200) }
        let service = OpenCodeGoUsageService(
            transport: transport,
            configProvider: { nil },
            now: { Self.now }
        )

        let snapshot = try? await service.fetchSnapshot()
        #expect(snapshot == nil)
    }

    // MARK: - Helpers

    private static var cookieOnlyConfig: OpenCodeGoUsageService.DashboardConfig {
        OpenCodeGoUsageService.DashboardConfig(workspaceID: "wrk_TESTWORKSPACE00", authCookie: "test-cookie")
    }

    private static func makeResponse(body: String, status: Int) -> (Data, HTTPURLResponse) {
        let url = URL(string: "https://opencode.ai/_server")!
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

/// A mock `OpenCodeHTTPTransport` that serves canned responses per request.
private struct MockTransport: OpenCodeHTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}
#endif
