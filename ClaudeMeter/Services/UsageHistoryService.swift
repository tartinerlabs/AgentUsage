//
//  UsageHistoryService.swift
//  ClaudeMeter
//
//  Service for persisting and managing usage history data
//

import Foundation
import ClaudeMeterKit
import OSLog

/// Service for managing historical usage data
actor UsageHistoryService {
    static let shared = UsageHistoryService()

    private let storageKey = "usageHistory"
    private var history: UsageHistory

    private init() {
        history = Self.loadFromStorage()
    }

    // MARK: - Public API

    /// Record a new snapshot to history
    func record(snapshot: UsageSnapshot) {
        history.record(snapshot: snapshot)
        saveToStorage()
        Logger.history.debug("Recorded usage snapshot to history")
    }

    /// Get the current usage history
    func getHistory() -> UsageHistory {
        history
    }

    /// Get records for the last N days
    func getRecords(days: Int) -> [DailyUsageRecord] {
        history.last(days)
    }

    /// Clear all history
    func clear() {
        history = UsageHistory()
        saveToStorage()
        Logger.history.info("Cleared usage history")
    }

    // MARK: - Persistence

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.history.error("Failed to save usage history: \(error.localizedDescription)")
        }
    }

    private static func loadFromStorage() -> UsageHistory {
        guard let data = UserDefaults.standard.data(forKey: "usageHistory"),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data) else {
            return UsageHistory()
        }
        return history
    }
}
