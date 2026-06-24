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
        /// Site origin — used for the `Origin` request header (scheme+host only, no path)
        /// that Better Auth's CSRF guard requires.
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
        /// Must equal the Better Auth base URL (the OIDC `issuer`); the provider's
        /// `checkResource` only accepts its own baseURL as a valid audience, and the
        /// resource server verifies the token's `aud` against the same value.
        static let resource = "https://ruchern.dev/api/auth"
        static let clientName = "ClaudeMeter"
        static let tokensKeychainAccount = "blog-oauth-tokens"
        /// Persisted dynamically-registered client_id (UserDefaults).
        static let clientIDDefaultsKey = "blogOAuthClientID"
    }

    // MARK: - macOS Only (file system access)
    #if os(macOS)

    /// Expands a leading `~` against the current user's home directory.
    private nonisolated static func expandTilde(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Splits a comma-separated env value into trimmed, non-empty entries.
    private nonisolated static func envPaths(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Claude Code project logs. Honors `CLAUDE_CONFIG_DIR` (comma-separated) and
    /// `XDG_CONFIG_HOME`, falling back to `~/.claude` and `~/.config/claude`.
    nonisolated static var claudeProjectsDirectories: [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        let configDirs = envPaths(env["CLAUDE_CONFIG_DIR"])
        if !configDirs.isEmpty {
            return configDirs.map { dir in
                let base = expandTilde(dir, home: home)
                // Accept either a config dir or one already pointing at projects/.
                return base.lastPathComponent == "projects" ? base : base.appendingPathComponent("projects")
            }
        }

        let configBase: URL = {
            if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return expandTilde(xdg, home: home)
            }
            return home.appendingPathComponent(".config")
        }()

        return [
            home.appendingPathComponent(".claude/projects"),
            configBase.appendingPathComponent("claude/projects")
        ]
    }

    /// Codex CLI session rollout logs (`rollout-*.jsonl`), nested by year/month/day.
    /// Honors `CODEX_HOME` (comma-separated) and includes `archived_sessions/`.
    nonisolated static var codexSessionsDirectories: [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var bases = envPaths(env["CODEX_HOME"]).map { expandTilde($0, home: home) }
        if bases.isEmpty {
            bases = [home.appendingPathComponent(".codex")]
        }
        return bases.flatMap {
            [$0.appendingPathComponent("sessions"), $0.appendingPathComponent("archived_sessions")]
        }
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

    /// OpenCode data directories. Honors `OPENCODE_DATA_DIR` (comma-separated) and
    /// `XDG_DATA_HOME`, falling back to `~/.local/share/opencode`.
    nonisolated static var openCodeDataDirectories: [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        var dirs = envPaths(env["OPENCODE_DATA_DIR"]).map { expandTilde($0, home: home) }
        if let xdgData = env["XDG_DATA_HOME"], !xdgData.isEmpty {
            dirs.append(expandTilde(xdgData, home: home).appendingPathComponent("opencode"))
        }
        dirs.append(home.appendingPathComponent(".local/share/opencode"))
        return dirs
    }

    /// OpenCode SQLite database candidates, derived from `openCodeDataDirectories`.
    nonisolated static var openCodeDatabaseURLs: [URL] {
        openCodeDataDirectories.map { $0.appendingPathComponent("opencode.db") }
    }
    #endif
}
