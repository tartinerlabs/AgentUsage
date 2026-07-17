//
//  WidgetUsageProvider.swift
//  AgentUsageKit
//
//  Lets the widget extension refresh usage on its own timeline, independent of
//  whether the main app is running. Reads the shared Keychain token, fetches
//  live usage, and writes it to the shared App Group cache.
//

import Foundation
import OSLog

/// Fetches live Claude usage for the widget timeline and caches the result.
public enum WidgetUsageProvider: Sendable {
    private static let logger = Logger(subsystem: "com.tartinerlabs.AgentUsage", category: "WidgetFetch")

    /// Fetch live usage using the stored Claude token and persist it to the
    /// shared cache.
    /// - Returns: The fresh snapshot, or `nil` when there is no stored token or
    ///   the fetch fails — the caller should fall back to the cached snapshot.
    public static func refresh() async -> UsageSnapshot? {
        guard let token = ClaudeCredentialStore.loadAccessToken() else {
            logger.debug("No stored Claude token — widget will use cached snapshot")
            return nil
        }

        do {
            let snapshot = try await ClaudeUsageService().fetchUsage(token: token)
            WidgetDataStorage.shared.save(snapshot)
            logger.debug("Widget fetched and cached live usage")
            return snapshot
        } catch {
            logger.debug("Widget live fetch failed — falling back to cached snapshot")
            return nil
        }
    }
}
