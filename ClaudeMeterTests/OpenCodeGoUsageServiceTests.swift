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
    @Test func parsesDashboardUsageWindows() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let html = #"""
        rollingUsage:$R[1]={status:"active",usagePercent:12.5,resetInSec:3600}
        weeklyUsage:$R[2]={status:"active",resetInSec:604800,usagePercent:34}
        monthlyUsage:{"status":"active","usagePercent":"56.75","resetInSec":"1209600"}
        """#

        let snapshot = try #require(OpenCodeGoUsageService.parseDashboardHTML(html, now: now))

        #expect(snapshot.provider == .openCode)
        #expect(snapshot.planName == "Go")
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows.map(\.windowType) == [.openCodeGoFiveHour, .openCodeGoWeekly, .openCodeGoMonthly])
        #expect(snapshot.windows[0].utilization == 12.5)
        #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(3600))
        #expect(snapshot.windows[1].utilization == 34)
        #expect(snapshot.windows[1].resetsAt == now.addingTimeInterval(604800))
        #expect(snapshot.windows[2].utilization == 56.75)
        #expect(snapshot.windows[2].resetsAt == now.addingTimeInterval(1209600))
    }

    @Test func parsesEscapedDashboardPayload() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let html = #"rollingUsage:{\"usagePercent\":64,\"resetInSec\":90}"#

        let snapshot = try #require(OpenCodeGoUsageService.parseDashboardHTML(html, now: now))

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].windowType == .openCodeGoFiveHour)
        #expect(snapshot.windows[0].utilization == 64)
        #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(90))
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
}
#endif
