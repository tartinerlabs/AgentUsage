//
//  CursorUsageServiceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import Testing
@testable import ClaudeMeter
import ClaudeMeterKit

@Suite("Cursor Usage Service")
struct CursorUsageServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func object(_ json: String) throws -> [String: Any] {
        try #require(CursorUsageService.jsonObject(Data(json.utf8)))
    }

    @Test func mapsPlanUsageWindowsAndOnDemandSpend() throws {
        // billingCycleEnd is epoch-ms; money fields are integer cents.
        let usage = try object(#"""
        {
          "enabled": true,
          "billingCycleStart": 1799000000000,
          "billingCycleEnd": 1801592000000,
          "planUsage": {
            "totalPercentUsed": 42.5,
            "autoPercentUsed": 30,
            "apiPercentUsed": 12.5,
            "limit": 2000,
            "remaining": 1150
          },
          "spendLimitUsage": {
            "individualLimit": 5000,
            "individualRemaining": 3800,
            "individualUsed": 1200
          }
        }
        """#)

        let snapshot = try #require(CursorUsageService.mapUsage(usage, planName: "Pro", now: now))

        #expect(snapshot.provider == .cursor)
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.windows.map(\.windowType) == [.cursorTotal, .cursorAuto, .cursorApi])
        #expect(snapshot.windows[0].utilization == 42.5)
        #expect(snapshot.windows[1].utilization == 30)
        #expect(snapshot.windows[2].utilization == 12.5)
        // resetsAt derived from billingCycleEnd (ms → s).
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_801_592_000))

        let extra = try #require(snapshot.extraUsage)
        #expect(extra.used == 12)      // 1200 cents → $12
        #expect(extra.limit == 50)     // 5000 cents → $50
        #expect(extra.currencyCode == "USD")
    }

    @Test func mapsPercentOnlyPlanUsageWithOverallSpendLimit() throws {
        // Live shape: planUsage carries only percentages; spendLimitUsage uses overall* fields
        // and exposes no explicit "used", so spend is derived as limit − remaining.
        let usage = try object(#"""
        {
          "billingCycleEnd": 1801592000000,
          "planUsage": { "totalPercentUsed": 60, "autoPercentUsed": 40, "apiPercentUsed": 0 },
          "spendLimitUsage": {
            "overallLimit": 5000,
            "overallRemaining": 2000,
            "individualLimit": 0,
            "pooledLimit": 0,
            "limitType": "user"
          }
        }
        """#)

        let snapshot = try #require(CursorUsageService.mapUsage(usage, planName: "Free", now: now))
        #expect(snapshot.windows.map(\.windowType) == [.cursorTotal, .cursorAuto, .cursorApi])
        #expect(snapshot.windows[0].utilization == 60)
        let extra = try #require(snapshot.extraUsage)
        #expect(extra.limit == 50)  // 5000 cents → $50
        #expect(extra.used == 30)   // (5000 - 2000) cents → $30
    }

    @Test func noSpendCardWhenAllSpendLimitsZero() throws {
        // The common Free-plan live shape: every spend limit is 0 → no extra-usage card.
        let usage = try object(#"""
        {
          "planUsage": { "totalPercentUsed": 0, "autoPercentUsed": 0, "apiPercentUsed": 0 },
          "spendLimitUsage": { "overallLimit": 0, "overallRemaining": 0, "individualLimit": 0, "pooledLimit": 0 }
        }
        """#)
        let snapshot = try #require(CursorUsageService.mapUsage(usage, planName: "Free", now: now))
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.extraUsage == nil)
    }

    @Test func derivesTotalPercentFromLimitWhenAbsent() throws {
        let usage = try object(#"""
        {
          "enabled": true,
          "planUsage": { "limit": 4000, "remaining": 1000 }
        }
        """#)

        let snapshot = try #require(CursorUsageService.mapUsage(usage, planName: nil, now: now))
        // used = limit - remaining = 3000 cents; 3000/4000 = 75%.
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].windowType == .cursorTotal)
        #expect(snapshot.windows[0].utilization == 75)
        #expect(snapshot.extraUsage == nil)
        #expect(snapshot.planName == nil)
    }

    @Test func returnsNilWhenNoPlanUsage() throws {
        let disabled = try object(#"{ "enabled": false, "planUsage": { "limit": 100 } }"#)
        #expect(CursorUsageService.mapUsage(disabled, planName: nil, now: now) == nil)

        let missing = try object(#"{ "enabled": true }"#)
        #expect(CursorUsageService.mapUsage(missing, planName: nil, now: now) == nil)

        let unusable = try object(#"{ "enabled": true, "planUsage": { "foo": 1 } }"#)
        #expect(CursorUsageService.mapUsage(unusable, planName: nil, now: now) == nil)
    }

    @Test func mapsLegacyRequestQuota() throws {
        let usage = try object(#"""
        {
          "gpt-4": { "numRequests": 125, "maxRequestUsage": 500 },
          "startOfMonth": "2025-01-01T00:00:00.000Z"
        }
        """#)

        let snapshot = try #require(CursorUsageService.mapRequestBased(usage, planName: "Free", now: now))
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].windowType == .cursorRequests)
        #expect(snapshot.windows[0].utilization == 25)  // 125/500
    }

    @Test func requestQuotaRequiresValidLimit() throws {
        let usage = try object(#"{ "gpt-4": { "numRequests": 10, "maxRequestUsage": 0 } }"#)
        #expect(CursorUsageService.mapRequestBased(usage, planName: nil, now: now) == nil)
    }

    @Test func derivesUserIDFromJWTSubject() {
        // JWT with payload {"sub":"auth0|user_ABC123"}; signature irrelevant to parsing.
        let payload = Data(#"{"sub":"auth0|user_ABC123"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payload).sig"
        #expect(CursorUsageService.jwtUserID(token) == "user_ABC123")
    }
}
#endif
