//
//  LiveActivityAttributes.swift
//  ClaudeMeter
//
//  Shared Live Activity types for both main app and widget extension
//

#if os(iOS)
import ActivityKit
import ClaudeMeterKit
import SwiftUI

// MARK: - MetricType

/// The type of usage metric to track
enum MetricType: String, CaseIterable, Identifiable {
    case session
    case opus
    case sonnet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return "Current session"
        case .opus: return "All models"
        case .sonnet: return "Sonnet"
        }
    }
}

// MARK: - Live Activity Attributes

/// Attributes for Claude usage Live Activity
struct ClaudeMeterLiveActivityAttributes: ActivityAttributes {
    /// Fixed properties set when activity starts
    var selectedMetric: String  // "Session", "Opus", or "Sonnet"

    /// Dynamic properties updated over time
    public struct ContentState: Codable, Hashable {
        var percentUsed: Int
        var timeUntilReset: String
        var statusRaw: String  // "onTrack", "warning", "critical"

        var status: UsageStatus {
            UsageStatus(rawValue: statusRaw) ?? .onTrack
        }

        /// Create from UsageWindow
        init(from window: UsageWindow) {
            self.percentUsed = window.percentUsed
            self.timeUntilReset = window.timeUntilReset
            self.statusRaw = window.status.rawValue
        }

        init(percentUsed: Int, timeUntilReset: String, statusRaw: String) {
            self.percentUsed = percentUsed
            self.timeUntilReset = timeUntilReset
            self.statusRaw = statusRaw
        }
    }
}
#endif
