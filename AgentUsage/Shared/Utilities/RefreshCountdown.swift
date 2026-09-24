//
//  RefreshCountdown.swift
//  AgentUsage
//
//  Compact countdown to the next scheduled auto-refresh, e.g. "next in 3m".
//

import Foundation

nonisolated enum RefreshCountdown {
    /// Countdown text for the next scheduled refresh, or `nil` when none is scheduled
    /// (Manual refresh, schedule stopped, or a scheduled refresh already in flight).
    ///
    /// Whole minutes round down so the value steps 2m → 1m → <1m; a refresh that is
    /// due or overdue also reads "<1m" rather than a negative or zero duration.
    static func text(until next: Date?, now: Date) -> String? {
        guard let next else { return nil }
        let minutes = Int(next.timeIntervalSince(now) / 60)
        guard minutes >= 1 else { return "next in <1m" }
        guard minutes >= 60 else { return "next in \(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "next in \(hours)h" : "next in \(hours)h \(remainder)m"
    }
}
