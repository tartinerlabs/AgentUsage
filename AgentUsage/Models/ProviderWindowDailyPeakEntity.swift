//
//  ProviderWindowDailyPeakEntity.swift
//  AgentUsage
//

import AgentUsageKit
import Foundation
import SwiftData

/// Provider-neutral daily peak used by the reliability engine.
@Model
final class ProviderWindowDailyPeakEntity {
    @Attribute(.unique) var id: String
    var providerID: String
    var windowID: String
    var windowLabel: String
    var date: Date
    var peakUtilization: Double
    var updatedAt: Date

    init(
        provider: Provider,
        window: UsageWindow,
        date: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let day = Calendar.current.startOfDay(for: date)
        self.id = Self.id(provider: provider, windowID: window.windowID, date: day)
        self.providerID = provider.rawValue
        self.windowID = window.windowID.rawValue
        self.windowLabel = window.displayName
        self.date = day
        self.peakUtilization = window.utilization
        self.updatedAt = updatedAt
    }

    func merge(window: UsageWindow, updatedAt: Date = Date()) {
        windowLabel = window.displayName
        peakUtilization = max(peakUtilization, window.utilization)
        self.updatedAt = updatedAt
    }

    static func id(provider: Provider, windowID: UsageWindowID, date: Date) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(provider.rawValue)|\(windowID.rawValue)|\(day)"
    }
}
