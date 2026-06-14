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

    /// Full URL for the Anthropic OAuth usage endpoint.
    static var usageURL: URL {
        URL(string: apiBaseURL + apiUsagePath)!
    }

    // MARK: - Codex (ChatGPT subscription live usage)
    /// Server-side ChatGPT quota endpoint. Reflects usage from both Codex CLI and
    /// OpenCode-via-ChatGPT, unlike the stale local rollout logs.
    static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let codexTokenRefreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let codexOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let codexAccountIDHeader = "ChatGPT-Account-Id"
    static let codexPrimaryUsedPercentHeader = "x-codex-primary-used-percent"
    static let codexSecondaryUsedPercentHeader = "x-codex-secondary-used-percent"

    // MARK: - Provider Links (status / console dashboards)
    static let anthropicStatusURL = "https://status.anthropic.com"
    static let anthropicConsoleURL = "https://claude.ai/settings/usage"
    static let openaiStatusURL = "https://status.openai.com"
    static let openaiPlatformURL = "https://platform.openai.com/usage"

    // MARK: - Network Configuration
    static let requestTimeout: TimeInterval = 30
    static let maxRetryAttempts = 3
    static let initialRetryDelay: TimeInterval = 1.0
    static let retryBackoffMultiplier: Double = 2.0

    // MARK: - Claude Code Keychain
    static let claudeCodeKeychainService = "Claude Code-credentials"
    static var claudeCodeKeychainAccount: String {
        NSUserName()
    }

    // MARK: - Blog OAuth (Better Auth OAuth 2.1 / OIDC provider)
    /// OAuth Authorization Code + PKCE flow used to authenticate the blog usage sync.
    /// ClaudeMeter self-registers as a public client (dynamic registration) and exchanges
    /// the code for a JWKS-verifiable JWT access token. See `BlogOAuthService`.
    enum BlogOAuth {
        static let issuer = "https://ruchern.dev"
        static let discoveryURL = URL(string: "https://ruchern.dev/api/auth/.well-known/openid-configuration")!
        static let authorizeURL = URL(string: "https://ruchern.dev/api/auth/oauth2/authorize")!
        static let tokenURL = URL(string: "https://ruchern.dev/api/auth/oauth2/token")!
        static let registerURL = URL(string: "https://ruchern.dev/api/auth/oauth2/register")!
        static let userinfoURL = URL(string: "https://ruchern.dev/api/auth/oauth2/userinfo")!
        static let redirectURI = "claudemeter://oauth-callback"
        static let callbackScheme = "claudemeter"
        static let scopes = "openid profile email offline_access mcp"
        /// RFC 8707 resource indicator — ensures the access token is issued as a JWT.
        static let resource = "https://ruchern.dev"
        static let clientName = "ClaudeMeter"
        static let tokensKeychainAccount = "blog-oauth-tokens"
        /// Persisted dynamically-registered client_id (UserDefaults).
        static let clientIDDefaultsKey = "blogOAuthClientID"
    }

    // MARK: - macOS Only (file system access)
    #if os(macOS)

    nonisolated static var claudeProjectsDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects")
        ]
    }

    /// Codex CLI session rollout logs (`rollout-*.jsonl`), nested by year/month/day.
    nonisolated static var codexSessionsDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/sessions")
        ]
    }

    /// Codex CLI OAuth credentials (`auth.json`). Honors `CODEX_HOME`, then default locations.
    /// Used as the bearer-token source for the live `/wham/usage` fetch.
    nonisolated static var codexAuthFileURLs: [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        if let codexHome = env["CODEX_HOME"], !codexHome.isEmpty {
            urls.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }
        urls.append(home.appendingPathComponent(".codex/auth.json"))
        urls.append(home.appendingPathComponent(".config/codex/auth.json"))
        return urls
    }

    /// OpenCode SQLite database (XDG data home, with fallback).
    nonisolated static var openCodeDatabaseURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        if let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgData.isEmpty {
            urls.append(URL(fileURLWithPath: xdgData).appendingPathComponent("opencode/opencode.db"))
        }
        urls.append(home.appendingPathComponent(".local/share/opencode/opencode.db"))
        return urls
    }
    #endif
}
