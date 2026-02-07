//
//  Constants.swift
//  ClaudeMeter
//

import Foundation
import SwiftUI

enum Constants {
    // MARK: - Window IDs
    static let mainWindowID = "main-window"

    // MARK: - Brand Colors
    static let brandPrimary = Color(red: 193/255, green: 95/255, blue: 60/255)  // #C15F3C (Crail)
    static let brandSecondary = Color(red: 218/255, green: 119/255, blue: 86/255)  // #DA7756
    static let brandBackground = Color(red: 244/255, green: 243/255, blue: 238/255)  // #F4F3EE (Pampas)
    static let extraUsageAccent = Color(red: 139/255, green: 94/255, blue: 131/255)  // #8B5E83 (Dusty Plum)

    // MARK: - API
    static let apiBaseURL = "https://api.anthropic.com"
    static let apiUsagePath = "/api/oauth/usage"
    static let anthropicBetaHeader = "oauth-2025-04-20"

    static var usageURL: URL {
        URL(string: apiBaseURL + apiUsagePath)!
    }

    // MARK: - Network Configuration
    static let requestTimeout: TimeInterval = 30
    static let maxRetryAttempts = 3
    static let initialRetryDelay: TimeInterval = 1.0
    static let retryBackoffMultiplier: Double = 2.0

    // MARK: - macOS Only (file system access)
    #if os(macOS)
    static var credentialsFileURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    nonisolated static var claudeProjectsDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects")
        ]
    }
    #endif
}
