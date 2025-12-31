//
//  UsageData.swift
//  ClaudeMeter
//

import Foundation
import SwiftUI

struct UsageWindow: Sendable {
    let utilization: Double  // API returns percentage (0-100), not decimal (0-1)
    let resetsAt: Date

    var percentUsed: Int {
        Int(utilization)
    }

    var normalized: Double {
        min(max(utilization / 100.0, 0), 1)  // Clamped 0-1 for Gauge/ProgressView
    }

    var color: Color {
        switch normalized {
        case 0..<0.5: .green
        case 0.5..<0.8: .yellow
        default: .red
        }
    }

    var timeUntilReset: String {
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct UsageSnapshot: Sendable {
    let session: UsageWindow
    let weekly: UsageWindow
    let fetchedAt: Date

    var lastUpdatedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }
}
