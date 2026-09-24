//
//  RefreshCountdownTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
@testable import AgentUsage

@Suite("RefreshCountdown")
struct RefreshCountdownTests {
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func text(in seconds: TimeInterval) -> String? {
        RefreshCountdown.text(until: Self.now.addingTimeInterval(seconds), now: Self.now)
    }

    @Test func hiddenWhenNothingIsScheduled() {
        #expect(RefreshCountdown.text(until: nil, now: Self.now) == nil)
    }

    @Test func roundsWholeMinutesDown() {
        #expect(text(in: 3 * 60 + 30) == "next in 3m")
        #expect(text(in: 2 * 60) == "next in 2m")
        #expect(text(in: 2 * 60 - 1) == "next in 1m")
        #expect(text(in: 60) == "next in 1m")
        #expect(text(in: 15 * 60) == "next in 15m")
    }

    @Test func underAMinuteDueOrOverdueReadsLessThanAMinute() {
        #expect(text(in: 59) == "next in <1m")
        #expect(text(in: 0) == "next in <1m")
        #expect(text(in: -10) == "next in <1m")
        #expect(text(in: -300) == "next in <1m")
    }

    @Test func longWaitsUseHours() {
        #expect(text(in: 60 * 60) == "next in 1h")
        #expect(text(in: 65 * 60) == "next in 1h 5m")
        #expect(text(in: 2 * 60 * 60 + 30) == "next in 2h")
    }

    @Test @MainActor func footerTextAppendsTheCountdown() {
        #expect(
            LastUpdatedLabel.text(relativeText: "2 min. ago", nextRefreshText: "next in 3m")
                == "Updated 2 min. ago · next in 3m"
        )
        #expect(
            LastUpdatedLabel.text(relativeText: "just now", nextRefreshText: nil)
                == "Updated just now"
        )
    }
}
