//
//  UsageData.swift
//  ClaudeMeterWidgets
//
//  Shared models for widget extension
//  Note: This is a copy of the main app's UsageData.swift for widget target membership
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
    case session
    case opus
    case sonnet

    var totalDuration: TimeInterval {
        switch self {
        case .session: 5 * 60 * 60
        case .opus: 7 * 24 * 60 * 60
        case .sonnet: 7 * 24 * 60 * 60
        }
    }
}

struct UsageWindow: Sendable, Codable {
    let utilization: Double
    let resetsAt: Date
    let windowType: UsageWindowType

    var percentUsed: Int {
        Int(utilization)
    }

    var normalized: Double {
        min(max(utilization / 100.0, 0), 1)
    }

    var timeUntilReset: String {
        timeUntilReset(from: Date())
    }

    func timeUntilReset(from now: Date) -> String {
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

    var status: UsageStatus {
        let timeRemaining = resetsAt.timeIntervalSinceNow
        guard timeRemaining > 0 else { return .onTrack }

        let totalDuration = windowType.totalDuration
        let timeElapsed = totalDuration - timeRemaining
        let timeElapsedRatio = timeElapsed / totalDuration
        let expectedUsage = timeElapsedRatio * 100
        let difference = utilization - expectedUsage

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
    let opus: UsageWindow
    let sonnet: UsageWindow?
    let fetchedAt: Date

    var lastUpdatedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }

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
