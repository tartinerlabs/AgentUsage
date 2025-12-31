//
//  ClaudeCredentials.swift
//  ClaudeMeter
//

import Foundation

// Root structure matching ~/.claude/.credentials.json
struct CredentialsFile: Codable {
    let claudeAiOauth: ClaudeOAuthCredentials?
}

struct ClaudeOAuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?  // milliseconds since epoch
    let scopes: [String]?
    let subscriptionType: String?
    let rateLimitTier: String?

    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: expiresAt / 1000)
    }

    var isExpired: Bool {
        guard let expiresAtDate else { return false }
        return expiresAtDate < Date()
    }

    var hasRequiredScope: Bool {
        guard let scopes else { return true }
        return scopes.contains("user:profile")
    }
}
