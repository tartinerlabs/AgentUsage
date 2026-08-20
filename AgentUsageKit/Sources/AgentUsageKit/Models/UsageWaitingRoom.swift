//
//  UsageWaitingRoom.swift
//  AgentUsageKit
//
//  Eligibility for short at-limit windows: Live Activity waiting rooms and
//  reset-alert arming. Pure functions so macOS and iOS share one policy.
//

import Foundation

/// Policy for treating a rate-limit window as a waiting room: the user has
/// hit a short quota and is watching the clock until it resets.
public enum UsageWaitingRoom: Sendable {
    /// ActivityKit ends Live Activities after eight hours. Waiting-room
    /// activities are only for windows that can finish inside that budget.
    public static let liveActivityMaxDuration: TimeInterval = 8 * 60 * 60

    /// Matches the existing reset-notification guard: only arm an alert when
    /// the window was actually near its limit.
    public static let nearLimitUtilization: Double = 90

    /// A provider window that currently qualifies for waiting-room treatment.
    public struct Candidate: Sendable {
        public let provider: Provider
        public let window: UsageWindow

        public init(provider: Provider, window: UsageWindow) {
            self.provider = provider
            self.window = window
        }

        public var selection: UsageActivitySelection {
            UsageActivitySelection(provider: provider, windowID: window.windowID)
        }

        /// Stable local-notification identifier for this window's reset instant.
        ///
        /// `resetsAt` is truncated to seconds so API timestamp jitter does not
        /// create duplicate pending requests.
        public var resetNotificationIdentifier: String {
            let seconds = Int(window.resetsAt.timeIntervalSince1970)
            return "reset.\(provider.rawValue).\(window.windowID.rawValue).\(seconds)"
        }
    }

    public static func isShortWindow(_ window: UsageWindow) -> Bool {
        window.totalDuration > 0 && window.totalDuration <= liveActivityMaxDuration
    }

    public static func remainingDuration(_ window: UsageWindow, now: Date) -> TimeInterval {
        window.resetsAt.timeIntervalSince(now)
    }

    /// A Live Activity waiting room: short rate window, at a hard limit,
    /// extra usage not already absorbing the overage, and reset still inside
    /// the eight-hour ActivityKit lifetime.
    public static func isLiveActivityEligible(
        provider: Provider,
        window: UsageWindow,
        now: Date
    ) -> Bool {
        guard provider.supports(.rateWindows) else { return false }
        guard isShortWindow(window) else { return false }
        guard !window.isExpired(from: now) else { return false }
        guard window.isAtLimit else { return false }
        guard !window.isUsingExtraUsage else { return false }
        let remaining = remainingDuration(window, now: now)
        return remaining > 0 && remaining <= liveActivityMaxDuration
    }

    /// Schedule a reset notification for any rate window that is near or at
    /// limit and has not yet expired. Weekly and monthly windows are included;
    /// those are the wrong shape for a Live Activity but still worth a ping.
    public static func needsResetAlert(
        provider: Provider,
        window: UsageWindow,
        now: Date
    ) -> Bool {
        guard provider.supports(.rateWindows) else { return false }
        guard !window.isExpired(from: now) else { return false }
        guard window.utilization >= nearLimitUtilization else { return false }
        return window.resetsAt > now
    }

    public static func liveActivityCandidates(
        from snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> [Candidate] {
        candidates(from: snapshots) { provider, window in
            isLiveActivityEligible(provider: provider, window: window, now: now)
        }
        .sorted { $0.window.resetsAt < $1.window.resetsAt }
    }

    public static func nextLiveActivityCandidate(
        from snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> Candidate? {
        liveActivityCandidates(from: snapshots, now: now).first
    }

    public static func resetAlertCandidates(
        from snapshots: [ProviderUsageSnapshot],
        now: Date
    ) -> [Candidate] {
        candidates(from: snapshots) { provider, window in
            needsResetAlert(provider: provider, window: window, now: now)
        }
    }

    private static func candidates(
        from snapshots: [ProviderUsageSnapshot],
        matching: (Provider, UsageWindow) -> Bool
    ) -> [Candidate] {
        snapshots.flatMap { snapshot in
            snapshot.windows.compactMap { window in
                guard matching(snapshot.provider, window) else { return nil }
                return Candidate(provider: snapshot.provider, window: window)
            }
        }
    }
}
