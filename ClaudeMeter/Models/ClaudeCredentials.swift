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

    /// Human-readable plan name for display, including any rate-limit tier
    /// multiplier encoded in `rateLimitTier` (e.g. `"default_claude_max_5x"`
    /// collapses to `"Max 5x"`).
    var planDisplayName: String {
        guard let subscriptionType,
              !subscriptionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "Free" }

        let base: String
        switch subscriptionType.lowercased() {
        case "max", "claude_max":       base = "Max"
        case "pro", "claude_pro":       base = "Pro"
        case "team", "claude_team":     base = "Team"
        case "enterprise":              base = "Enterprise"
        case "free":                    base = "Free"
        default:                        base = subscriptionType.capitalized
        }

        guard let rateLimitTier,
              let match = rateLimitTier.range(
                  of: #"\d+x"#,
                  options: [.regularExpression, .caseInsensitive]
              )
        else { return base }
        return "\(base) \(rateLimitTier[match].lowercased())"
    }
}
