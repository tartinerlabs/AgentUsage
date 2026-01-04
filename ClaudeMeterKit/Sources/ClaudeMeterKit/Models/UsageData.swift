//
//  UsageData.swift
//  ClaudeMeterKit
//
//  Shared models for usage data across app and extensions
//

import Foundation
import SwiftUI

// MARK: - Usage Status

public enum UsageStatus: String, Sendable, Codable {
    case onTrack
    case warning
    case critical

    public var label: String {
        switch self {
        case .onTrack: "Low"
        case .warning: "Moderate"
        case .critical: "High"
        }
    }

    public var icon: String {
        switch self {
        case .onTrack: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .onTrack: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Usage Window Type

public enum UsageWindowType: String, Sendable, Codable {
    case session  // 5 hours (five_hour)
    case opus     // 7 days - default weekly limit (seven_day)
    case sonnet   // 7 days - separate Sonnet limit (seven_day_sonnet)

    public var displayName: String {
        switch self {
        case .session: "Current session"
        case .opus: "All models"
        case .sonnet: "Sonnet"
        }
    }

    public var totalDuration: TimeInterval {
        switch self {
        case .session: 5 * 60 * 60      // 5 hours in seconds
        case .opus: 7 * 24 * 60 * 60    // 7 days in seconds
        case .sonnet: 7 * 24 * 60 * 60  // 7 days in seconds
        }
    }
}

// MARK: - Usage Window

public struct UsageWindow: Sendable, Codable {
    public let utilization: Double  // API returns percentage (0-100), not decimal (0-1)
    public let resetsAt: Date
    public let windowType: UsageWindowType

    public init(utilization: Double, resetsAt: Date, windowType: UsageWindowType) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.windowType = windowType
    }

    public var percentUsed: Int {
        Int(utilization)
    }

    public var isAtLimit: Bool {
        utilization >= 100
    }

    public var normalized: Double {
        min(max(utilization / 100.0, 0), 1)  // Clamped 0-1 for Gauge/ProgressView
    }

    public var timeUntilReset: String {
        timeUntilReset(from: Date())
    }

    public func timeUntilReset(from now: Date) -> String {
        let interval = resetsAt.timeIntervalSince(now)
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
    public var status: UsageStatus {
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

// MARK: - Usage Snapshot

public struct UsageSnapshot: Sendable, Codable {
    public let session: UsageWindow
    public let opus: UsageWindow      // Weekly default limit (was "seven_day")
    public let sonnet: UsageWindow?   // Separate Sonnet limit (if available)
    public let fetchedAt: Date

    public init(session: UsageWindow, opus: UsageWindow, sonnet: UsageWindow?, fetchedAt: Date) {
        self.session = session
        self.opus = opus
        self.sonnet = sonnet
        self.fetchedAt = fetchedAt
    }

    public var lastUpdatedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }

    /// Placeholder data for widget previews
    public static let placeholder = UsageSnapshot(
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
