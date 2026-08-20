//
//  UsageWaitingRoomTests.swift
//  AgentUsageKitTests
//

import Foundation
import Testing
@testable import AgentUsageKit

@Suite("UsageWaitingRoom")
struct UsageWaitingRoomTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func fiveHourSessionAtLimitIsLiveActivityEligible() {
        let window = makeWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(4 * 3600),
            type: .session
        )

        #expect(
            UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: window,
                now: now
            )
        )
        #expect(
            UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func weeklyWindowAtLimitGetsResetAlertOnly() {
        let window = makeWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(3 * 24 * 3600),
            type: .opus
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: window,
                now: now
            )
        )
        #expect(
            UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func grokNeverQualifiesWithoutRateWindows() {
        let window = makeWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(3600),
            type: .session
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .grok,
                window: window,
                now: now
            )
        )
        #expect(
            !UsageWaitingRoom.needsResetAlert(
                provider: .grok,
                window: window,
                now: now
            )
        )
    }

    @Test func extraUsageSessionIsNotALiveActivityWaitingRoom() {
        let window = makeWindow(
            utilization: 115,
            resetsAt: now.addingTimeInterval(2 * 3600),
            type: .session
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: window,
                now: now
            )
        )
        #expect(
            UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func ninetyPercentArmsResetAlertButNotLiveActivity() {
        let window = makeWindow(
            utilization: 90,
            resetsAt: now.addingTimeInterval(3600),
            type: .session
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: window,
                now: now
            )
        )
        #expect(
            UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func eightyNinePercentIsBelowResetAlertThreshold() {
        let window = makeWindow(
            utilization: 89,
            resetsAt: now.addingTimeInterval(3600),
            type: .session
        )

        #expect(
            !UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func expiredAndZeroDurationWindowsAreExcluded() {
        let expired = makeWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(-60),
            type: .session
        )
        let custom = UsageWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(3600),
            windowID: "cursor.dynamic.usage",
            displayName: "Usage",
            totalDuration: 0
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: expired,
                now: now
            )
        )
        #expect(
            !UsageWaitingRoom.needsResetAlert(
                provider: .claude,
                window: expired,
                now: now
            )
        )
        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .cursor,
                window: custom,
                now: now
            )
        )
        #expect(
            UsageWaitingRoom.needsResetAlert(
                provider: .cursor,
                window: custom,
                now: now
            )
        )
    }

    @Test func remainingTimeBeyondEightHoursBlocksLiveActivity() {
        let window = UsageWindow(
            utilization: 100,
            resetsAt: now.addingTimeInterval(9 * 3600),
            windowID: "session",
            displayName: "Current session",
            totalDuration: 5 * 3600
        )

        #expect(
            !UsageWaitingRoom.isLiveActivityEligible(
                provider: .claude,
                window: window,
                now: now
            )
        )
    }

    @Test func nextLiveActivityCandidatePicksSoonestReset() {
        let later = makeSnapshot(
            provider: .claude,
            window: makeWindow(
                utilization: 100,
                resetsAt: now.addingTimeInterval(3 * 3600),
                type: .session
            )
        )
        let sooner = makeSnapshot(
            provider: .codex,
            window: makeWindow(
                utilization: 100,
                resetsAt: now.addingTimeInterval(1800),
                type: .codexFiveHour
            )
        )
        let weekly = makeSnapshot(
            provider: .claude,
            window: makeWindow(
                utilization: 100,
                resetsAt: now.addingTimeInterval(600),
                type: .opus
            )
        )

        let next = UsageWaitingRoom.nextLiveActivityCandidate(
            from: [later, sooner, weekly],
            now: now
        )

        #expect(next?.provider == .codex)
        #expect(next?.window.windowType == .codexFiveHour)
    }

    @Test func resetNotificationIdentifierTruncatesToSeconds() {
        let window = makeWindow(
            utilization: 100,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000.7),
            type: .session
        )
        let candidate = UsageWaitingRoom.Candidate(provider: .claude, window: window)

        #expect(candidate.resetNotificationIdentifier == "reset.claude.session.2000000000")
        #expect(
            candidate.selection
                == UsageActivitySelection(provider: .claude, windowID: window.windowID)
        )
    }

    private func makeWindow(
        utilization: Double,
        resetsAt: Date,
        type: UsageWindowType
    ) -> UsageWindow {
        UsageWindow(utilization: utilization, resetsAt: resetsAt, windowType: type)
    }

    private func makeSnapshot(
        provider: Provider,
        window: UsageWindow
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [window],
            fetchedAt: now
        )
    }
}
