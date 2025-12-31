//
//  Constants.swift
//  ClaudeMeter
//

import Foundation

enum Constants {
    static let apiBaseURL = "https://api.anthropic.com"
    static let apiUsagePath = "/api/oauth/usage"
    static let anthropicBetaHeader = "oauth-2025-04-20"

    static var credentialsFileURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    static var usageURL: URL {
        URL(string: apiBaseURL + apiUsagePath)!
    }
}
