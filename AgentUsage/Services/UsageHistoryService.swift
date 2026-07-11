//
//  UsageHistoryService.swift
//  AgentUsage
//
//  Service for persisting and managing usage history data
//

import Foundation
import AgentUsageKit
import OSLog
import SwiftData

/// Service for managing historical usage data
actor UsageHistoryService {
    static let shared = UsageHistoryService()
    nonisolated private static let logger = Logger(subsystem: "com.tartinerlabs.AgentUsage", category: "History")

    private let storageKey = "usageHistory"
    private let repository: UsageHistoryRepository?
    private let defaults: UserDefaults
    private var history: UsageHistory
    private var didMigrate = false

    init(repository: UsageHistoryRepository? = nil, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        self.history = Self.loadFromStorage(defaults: defaults)
    }

    // MARK: - Public API

    /// Record a new snapshot to history
    func record(snapshot: UsageSnapshot) async {
        if let repository {
            do {
                try await ensureMigrated(repository)
                try await repository.record(snapshot: snapshot)
                Self.logger.debug("Recorded usage snapshot to SwiftData history")
            } catch {
                Self.logger.error("Failed to save SwiftData usage history: \(error.localizedDescription)")
            }
            return
        }

        history.record(snapshot: snapshot)
        saveToStorage()
        Self.logger.debug("Recorded usage snapshot to history")
    }

    func record(providerSnapshot: ProviderUsageSnapshot) async {
        guard let repository else { return }
        do {
            try await ensureMigrated(repository)
            try await repository.record(providerSnapshot: providerSnapshot)
        } catch {
            Self.logger.error("Failed to save provider history: \(error.localizedDescription)")
        }
    }

    /// Get the current usage history
    func getHistory() async -> UsageHistory {
        if let repository {
            do {
                try await ensureMigrated(repository)
                return try await repository.fetchHistory()
            } catch {
                Self.logger.error("Failed to load SwiftData usage history: \(error.localizedDescription)")
                return history
            }
        }

        return history
    }

    /// Get records for the last N days
    func getRecords(days: Int) async -> [DailyUsageRecord] {
        if let repository {
            do {
                try await ensureMigrated(repository)
                return try await repository.fetchRecords(days: days)
            } catch {
                Self.logger.error("Failed to load SwiftData usage records: \(error.localizedDescription)")
                return history.last(days)
            }
        }

        return history.last(days)
    }

    /// Clear all history
    func clear() async {
        if let repository {
            do {
                try await repository.clear()
                history = UsageHistory()
                Self.logger.info("Cleared SwiftData usage history")
            } catch {
                Self.logger.error("Failed to clear SwiftData usage history: \(error.localizedDescription)")
            }
            return
        }

        history = UsageHistory()
        saveToStorage()
        Self.logger.info("Cleared usage history")
    }

    // MARK: - Persistence

    private func ensureMigrated(_ repository: UsageHistoryRepository) async throws {
        guard !didMigrate else { return }
        try await repository.migrateFromUserDefaultsIfNeeded(defaults: defaults)
        didMigrate = true
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(history)
            defaults.set(data, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to save usage history: \(error.localizedDescription)")
        }
    }

    private static func loadFromStorage(defaults: UserDefaults) -> UsageHistory {
        guard let data = defaults.data(forKey: "usageHistory"),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data) else {
            return UsageHistory()
        }
        return history
    }
}
