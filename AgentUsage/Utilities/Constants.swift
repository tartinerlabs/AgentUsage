//
//  Constants.swift
//  AgentUsage
//

import Foundation
import SwiftUI
import AgentUsageKit

/// `nonisolated` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
/// Without it every constant here is MainActor-isolated, and the actors that need them
/// (`ClaudeAPIService`, `CodexUsageService`, `BlogOAuthService`, the log sources) cannot read
/// them. These are immutable `Sendable` values, safe from any isolation.
nonisolated enum Constants {
    // MARK: - Branding
    /// User-facing product name shown in the UI (window/nav titles, About and Settings
    /// headings, notifications, share card). Single source of truth for in-app display.
    /// Keep in sync with `INFOPLIST_KEY_CFBundleDisplayName` in the build settings, which
    /// drives the OS-level name under the app icon and cannot reference this constant.
    static let appDisplayName = "Agent Usage"

    // MARK: - Window IDs
    static let mainWindowID = "main-window"

    // MARK: - App Group
    /// Shared App Group container identifier. Backs the SwiftData store, widget data
    /// sharing, and the security-scoped bookmark suite. Must match the
    /// `com.apple.security.application-groups` entitlement across all targets.
    static let appGroupIdentifier = "group.com.tartinerlabs.AgentUsage"

    // MARK: - Brand Colors
    static let iconPacificBlue = AgentUsageColors.iconPacificBlue
    static let brandPrimary = AgentUsageColors.usageProgress
    static let brandSecondary = AgentUsageColors.brandSecondary
    static let brandBackground = AgentUsageColors.brandBackground
    static let extraUsageAccent = AgentUsageColors.extraUsageAccent

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

    /// Dedicated reset-credits endpoint (per-credit expiry). Best-effort: the usage body's
    /// `rate_limit_reset_credits.available_count` is the count-only fallback. Requires extra
    /// headers the endpoint expects: `OpenAI-Beta: codex-1`, `originator: Codex Desktop`.
    static let codexResetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    // MARK: - Cursor (subscription live usage)
    /// Cursor does not document a personal-usage API. These are the same
    /// dashboard endpoints used by Cursor's own signed-in clients.
    static let cursorUsageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    static let cursorPlanURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
    static let cursorTokenRefreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    static let cursorUsageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let cursorLegacyUsageURL = URL(string: "https://cursor.com/api/usage")!
    static let cursorOAuthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let cursorConnectProtocolVersionHeader = "Connect-Protocol-Version"
    static let cursorKeychainAccessTokenService = "cursor-access-token"
    static let cursorKeychainRefreshTokenService = "cursor-refresh-token"
    static let cursorStateAccessTokenKey = "cursorAuth/accessToken"
    static let cursorStateRefreshTokenKey = "cursorAuth/refreshToken"
    static let cursorStateMembershipTypeKey = "cursorAuth/stripeMembershipType"

    // MARK: - Network Configuration
    static let requestTimeout: TimeInterval = 30
    static let maxRetryAttempts = 3
    static let initialRetryDelay: TimeInterval = 1.0
    static let retryBackoffMultiplier: Double = 2.0

    /// Upper bound on any single in-loop retry sleep. `Retry-After` can be minutes or
    /// hours; sleeping that long inside the API actor would serialize every later
    /// request behind it. Longer backoff is handled by `rateLimitedUntil` in the view
    /// model, which suppresses auto-refresh without holding the actor.
    static let maxRetryDelay: TimeInterval = 30

    /// Default cooldown after a rate-limit (HTTP 429) response with no `Retry-After`
    /// header. Auto-refresh is suppressed for this long so we stop hammering the
    /// endpoint that just throttled us.
    static let rateLimitCooldownFallback: TimeInterval = 120

    // MARK: - Continuity Sync (CloudKit)
    static let continuitySyncRevokedKey = "appConnectionRevoked"

    /// How stale a macOS-published snapshot may be before iOS stops treating it
    /// as fresh. iOS never fetches provider usage directly; it waits for the Mac
    /// to publish the next snapshot.
    static let syncFallbackThreshold: TimeInterval = 6 * 3600

    // MARK: - Claude Code Keychain
    static let claudeCodeKeychainService = "Claude Code-credentials"
    static var claudeCodeKeychainAccount: String {
        NSUserName()
    }

    // MARK: - Blog OAuth (Better Auth OAuth 2.1 / OIDC provider)
    /// OAuth Authorization Code + PKCE flow used to authenticate the blog usage sync.
    /// AgentUsage self-registers as a public client (dynamic registration) and exchanges
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
        static let redirectURI = "agentusage://oauth-callback"
        static let callbackScheme = "agentusage"
        static let scopes = "openid profile email offline_access mcp"
        /// RFC 8707 resource indicator — ensures the access token is issued as a JWT.
        /// Must equal the Better Auth base URL (the OIDC `issuer`); the provider's
        /// `checkResource` only accepts its own baseURL as a valid audience, and the
        /// resource server verifies the token's `aud` against the same value.
        static let resource = "https://ruchern.dev/api/auth"
        static let clientName = "AgentUsage"
        static let tokensKeychainAccount = "blog-oauth-tokens"
        /// Persisted dynamically-registered client_id (UserDefaults).
        static let clientIDDefaultsKey = "blogOAuthClientID"
    }

    // MARK: - macOS Only (file system access)
    #if os(macOS)

    /// The user's real home directory.
    ///
    /// Under the App Sandbox, `FileManager.homeDirectoryForCurrentUser` and
    /// `NSHomeDirectory()` return the app's *container* home
    /// (`~/Library/Containers/…/Data`), which does not contain the CLI tools' logs.
    /// `getpwuid(getuid())` returns the true home (`/Users/<name>`) even when
    /// sandboxed, which is what we need both to preset the folder-access panel and
    /// to build the real log paths that the security-scoped bookmarks grant access to.
    nonisolated static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = String(cString: dir)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Real per-provider root directories the user grants access to. Each granted
    /// directory covers its entire subtree (the paths below are all subpaths).
    nonisolated static var claudeHomeDirectory: URL {
        realHomeDirectory.appendingPathComponent(".claude")
    }
    nonisolated static var codexHomeDirectory: URL {
        realHomeDirectory.appendingPathComponent(".codex")
    }
    nonisolated static var openCodeHomeDirectory: URL {
        realHomeDirectory.appendingPathComponent(".local/share/opencode")
    }
    nonisolated static var cursorStateDirectory: URL {
        realHomeDirectory.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
    }
    /// Grok Build home (`GROK_HOME`, default `~/.grok`).
    nonisolated static var grokHomeDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let grokHome = env["GROK_HOME"], !grokHome.isEmpty {
            return URL(fileURLWithPath: grokHome, isDirectory: true)
        }
        return realHomeDirectory.appendingPathComponent(".grok")
    }
    nonisolated static var cursorStateDBURLs: [URL] {
        [cursorStateDirectory.appendingPathComponent("state.vscdb")]
    }

    /// Xcode's Coding Assistant bundles its own Claude Code and Codex agent homes,
    /// separate from the CLI ones. Sessions run from Xcode write only here, in the
    /// same on-disk formats. Note this lives outside every per-provider grant root
    /// above, so it is readable only under Full Disk Access or a home-folder grant.
    nonisolated static let xcodeCodingAssistantPath = "Library/Developer/Xcode/CodingAssistant"

    nonisolated static var claudeProjectsDirectories: [URL] {
        let home = realHomeDirectory
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
            home.appendingPathComponent("\(xcodeCodingAssistantPath)/ClaudeAgentConfig/projects")
        ]
    }

    /// Codex CLI session rollout logs (`rollout-*.jsonl`), nested by year/month/day.
    nonisolated static var codexSessionsDirectories: [URL] {
        let home = realHomeDirectory
        return [
            home.appendingPathComponent(".codex/sessions"),
            home.appendingPathComponent(".codex/archived_sessions"),
            home.appendingPathComponent("\(xcodeCodingAssistantPath)/codex/sessions")
        ]
    }

    /// Codex CLI OAuth credentials (`auth.json`). Honors `CODEX_HOME`, then default locations.
    /// Used as the bearer-token source for the live `/wham/usage` fetch.
    nonisolated static var codexAuthFileURLs: [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = realHomeDirectory
        var urls: [URL] = []
        if let codexHome = env["CODEX_HOME"], !codexHome.isEmpty {
            urls.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }
        urls.append(home.appendingPathComponent(".codex/auth.json"))
        urls.append(home.appendingPathComponent(".config/codex/auth.json"))
        return urls
    }

    /// Grok Build session directories (`summary.json` + `updates.jsonl` per session).
    nonisolated static var grokSessionsDirectories: [URL] {
        [grokHomeDirectory.appendingPathComponent("sessions")]
    }

    /// OpenCode SQLite database (XDG data home, with fallback).
    nonisolated static var openCodeDatabaseURLs: [URL] {
        let home = realHomeDirectory
        var urls: [URL] = []
        if let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgData.isEmpty {
            urls.append(URL(fileURLWithPath: xdgData).appendingPathComponent("opencode/opencode.db"))
        }
        urls.append(home.appendingPathComponent(".local/share/opencode/opencode.db"))
        return urls
    }
    #endif
}
