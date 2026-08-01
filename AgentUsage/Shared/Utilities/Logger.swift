//
//  Logger.swift
//  AgentUsage
//
//  Structured logging using OSLog for production-ready logging.
//  Logs appear in Console.app with proper categories for filtering.
//

import OSLog

/// `nonisolated` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which would otherwise make every category MainActor-isolated and unreachable from the
/// actors that do the logging. `Logger` is `Sendable` and safe to use from any isolation.
nonisolated extension Logger {
    /// Bundle identifier used as subsystem for all loggers
    private static let subsystem = "com.tartinerlabs.AgentUsage"

    // MARK: - Service Loggers

    /// API-related logging (network requests, responses, errors)
    static let api = Logger(subsystem: subsystem, category: "API")

    /// Credential loading and authentication logging
    static let credentials = Logger(subsystem: subsystem, category: "Credentials")

    /// Keychain operations logging
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// Token usage service logging (JSONL parsing, cost calculations)
    static let tokenUsage = Logger(subsystem: subsystem, category: "TokenUsage")

    /// Codex live-usage service logging (ChatGPT /wham/usage fetch, token refresh)
    static let codex = Logger(subsystem: subsystem, category: "Codex")

    /// Cursor live-usage service logging (dashboard usage and auth fallback)
    static let cursor = Logger(subsystem: subsystem, category: "Cursor")

    /// Notification service logging
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    /// Usage history service logging
    static let history = Logger(subsystem: subsystem, category: "History")

    /// Blog usage sync logging (log-root discovery, incremental indexing, upload)
    static let blogUsage = Logger(subsystem: subsystem, category: "BlogUsage")

    // MARK: - UI Loggers

    /// ViewModel logging (state changes, refresh operations)
    static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")

    /// Widget data management logging
    static let widget = Logger(subsystem: subsystem, category: "Widget")

    /// Live Activity management logging (iOS only)
    static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
}
