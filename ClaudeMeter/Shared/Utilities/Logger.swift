//
//  Logger.swift
//  ClaudeMeter
//
//  Structured logging using OSLog for production-ready logging.
//  Logs appear in Console.app with proper categories for filtering.
//

import OSLog

extension Logger {
    /// Bundle identifier used as subsystem for all loggers
    private static let subsystem = "com.tartinerlabs.ClaudeMeter"

    // MARK: - Service Loggers

    /// API-related logging (network requests, responses, errors)
    static let api = Logger(subsystem: subsystem, category: "API")

    /// Credential loading and authentication logging
    static let credentials = Logger(subsystem: subsystem, category: "Credentials")

    /// Keychain operations logging
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// Token usage service logging (JSONL parsing, cost calculations)
    static let tokenUsage = Logger(subsystem: subsystem, category: "TokenUsage")

    /// Notification service logging
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    /// Usage history service logging
    static let history = Logger(subsystem: subsystem, category: "History")

    // MARK: - UI Loggers

    /// ViewModel logging (state changes, refresh operations)
    static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")

    /// Widget data management logging
    static let widget = Logger(subsystem: subsystem, category: "Widget")

    /// Live Activity management logging (iOS only)
    static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
}
