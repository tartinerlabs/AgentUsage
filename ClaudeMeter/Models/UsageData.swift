//
//  UsageData.swift
//  ClaudeMeter
//

import Foundation
import SwiftUI

enum UsageStatus: String, Sendable, Codable {
    case onTrack
    case warning
    case critical

    var label: String {
        switch self {
        case .onTrack: "On track"
        case .warning: "Heavy usage"
        case .critical: "At risk"
        }
    }

    var icon: String {
        switch self {
        case .onTrack: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .onTrack: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

enum UsageWindowType: String, Sendable, Codable {
    case session  // 5 hours (five_hour)
    case opus     // 7 days - default weekly limit (seven_day)
    case sonnet   // 7 days - separate Sonnet limit (seven_day_sonnet)

    var totalDuration: TimeInterval {
        switch self {
        case .session: 5 * 60 * 60      // 5 hours in seconds
        case .opus: 7 * 24 * 60 * 60    // 7 days in seconds
        case .sonnet: 7 * 24 * 60 * 60  // 7 days in seconds
        }
    }
}

struct UsageWindow: Sendable, Codable {
    let utilization: Double  // API returns percentage (0-100), not decimal (0-1)
    let resetsAt: Date
    let windowType: UsageWindowType

    var percentUsed: Int {
        Int(utilization)
    }

    var normalized: Double {
        min(max(utilization / 100.0, 0), 1)  // Clamped 0-1 for Gauge/ProgressView
    }

    var timeUntilReset: String {
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "now" }

        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Calculate usage status based on absolute usage and consumption rate
    var status: UsageStatus {
        let timeRemaining = resetsAt.timeIntervalSinceNow
        guard timeRemaining > 0 else { return .onTrack }

        // Check absolute usage first - high usage is always concerning
        if utilization >= 90 {
            return .critical
        } else if utilization >= 75 {
            return .warning
        }

        // Then check pace relative to time elapsed
        let totalDuration = windowType.totalDuration
        let timeElapsed = totalDuration - timeRemaining
        let timeElapsedRatio = timeElapsed / totalDuration

        // Expected usage if consuming evenly over the window
        let expectedUsage = timeElapsedRatio * 100

        // How much ahead/behind schedule
        let difference = utilization - expectedUsage

        // Thresholds: within 10% is on track, within 25% is warning
        if difference <= 10 {
            return .onTrack
        } else if difference <= 25 {
            return .warning
        } else {
            return .critical
        }
    }
}

struct UsageSnapshot: Sendable, Codable {
    let session: UsageWindow
    let opus: UsageWindow      // Weekly default limit (was "seven_day")
    let sonnet: UsageWindow?   // Separate Sonnet limit (if available)
    let fetchedAt: Date

    var lastUpdatedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }

    /// Placeholder data for widget previews
    static let placeholder = UsageSnapshot(
        session: UsageWindow(
            utilization: 45,
            resetsAt: Date().addingTimeInterval(2.5 * 60 * 60),
            windowType: .session
        ),
        opus: UsageWindow(
            utilization: 32,
            resetsAt: Date().addingTimeInterval(4 * 24 * 60 * 60),
            windowType: .opus
        ),
        sonnet: UsageWindow(
            utilization: 28,
            resetsAt: Date().addingTimeInterval(5 * 24 * 60 * 60),
            windowType: .sonnet
        ),
        fetchedAt: Date()
    )
}
