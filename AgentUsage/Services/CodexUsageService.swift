//
//  CodexUsageService.swift
//  AgentUsage
//
//  Codex (ChatGPT subscription) rate-limit windows from the live usage API.
//

#if os(macOS)
import Foundation
import AgentUsageKit
import OSLog

/// Fetches the current Codex rate-limit windows from the ChatGPT backend.
///
/// The quota lives on the ChatGPT *account*, so it reflects usage from both the
/// Codex CLI and OpenCode-via-ChatGPT — unlike the local rollout logs, which only
/// the Codex CLI writes and which go stale (the old implementation read those and
/// fabricated a 0% window once a window's reset time had lapsed).
///
/// Bearer token comes from `~/.codex/auth.json` (`tokens.access_token`). On a 401
/// the token is refreshed once via `auth.openai.com/oauth/token`. The refreshed
/// token is kept in memory only — `auth.json` is owned by the Codex CLI and is
/// never written back, so there is no torn-write race.
actor CodexUsageService: ProviderUsageServiceProtocol {
    nonisolated let provider: Provider = .codex

    enum CodexError: LocalizedError {
        case unauthorized
        case sessionExpired
        case networkError(Error)
        case invalidResponse
        case serviceUnavailable
        case serverError(Int)
        case maxRetriesExceeded

        /// Whether this error should trigger a retry with backoff.
        var isRetryable: Bool {
            switch self {
            case .networkError, .serviceUnavailable:
                return true
            case .serverError(let code):
                return code >= 500 && code != 501
            case .unauthorized, .sessionExpired, .invalidResponse, .maxRetriesExceeded:
                return false
            }
        }

        var errorDescription: String? {
            switch self {
            case .unauthorized, .sessionExpired:
                return "Codex session expired. Run `codex` to log in again."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Codex usage API."
            case .serviceUnavailable:
                return "Codex usage API temporarily unavailable."
            case .serverError(let code):
                return "Codex usage API error: \(code)"
            case .maxRetriesExceeded:
                return "Failed after multiple retry attempts."
            }
        }
    }

    private struct CodexAuth {
        var accessToken: String
        let refreshToken: String?
        let accountID: String?
    }

    private let session: URLSession
    private let authFileURLs: [URL]
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        authFileURLs: [URL] = Constants.codexAuthFileURLs,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.authFileURLs = authFileURLs
        self.now = now
    }

    /// Returns the current Codex windows, or nil when usage is unavailable
    /// (not logged in, session expired). On transient errors it throws after
    /// exhausting retries; callers treat a nil/throw as "hide the Codex column"
    /// rather than fabricating a 0% window.
    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let auth = loadAuth() else {
            Logger.codex.info("No Codex auth.json found; skipping live usage fetch")
            return nil
        }

        var accessToken = auth.accessToken
        var didRefresh = false
        var lastError: CodexError?

        for attempt in 0..<Constants.maxRetryAttempts {
            do {
                let snapshot = try await performRequest(accessToken: accessToken, accountID: auth.accountID)
                return await enrichWithResetCredits(snapshot, accessToken: accessToken, accountID: auth.accountID)
            } catch let error as CodexError {
                lastError = error

                // On a 401, refresh the token once and retry immediately.
                if case .unauthorized = error {
                    guard !didRefresh, let refreshToken = auth.refreshToken else {
                        Logger.codex.error("Codex usage unauthorized; re-auth required")
                        return nil
                    }
                    didRefresh = true
                    do {
                        guard let refreshed = try await refreshAccessToken(refreshToken) else {
                            return nil
                        }
                        accessToken = refreshed
                        continue
                    } catch {
                        Logger.codex.error("Codex token refresh failed; re-auth required")
                        return nil
                    }
                }

                guard error.isRetryable else { throw error }

                if attempt < Constants.maxRetryAttempts - 1 {
                    let delay = calculateRetryDelay(attempt: attempt)
                    let attemptNumber = attempt + 1
                    let maxAttempts = Constants.maxRetryAttempts
                    let formattedDelay = String(format: "%.1f", delay)
                    Logger.codex.info(
                        "Codex usage request failed (attempt \(attemptNumber)/\(maxAttempts)). Retrying in \(formattedDelay)s..."
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Logger.codex.error("Codex usage request failed after \(Constants.maxRetryAttempts) attempts")
        throw lastError ?? CodexError.maxRetriesExceeded
    }

    // MARK: - Auth

    private func loadAuth() -> CodexAuth? {
        for url in authFileURLs {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = json["tokens"] as? [String: Any],
                  let access = tokens["access_token"] as? String,
                  !access.isEmpty else { continue }
            let refresh = tokens["refresh_token"] as? String
            let accountID = tokens["account_id"] as? String
            return CodexAuth(accessToken: access, refreshToken: refresh, accountID: accountID)
        }
        return nil
    }

    /// Refreshes the access token in memory. Never writes `auth.json` back.
    /// Returns nil if the response lacks a token; throws `.sessionExpired` when
    /// the refresh token itself is rejected.
    private func refreshAccessToken(_ refreshToken: String) async throws -> String? {
        var request = URLRequest(url: Constants.codexTokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Constants.requestTimeout

        let encodedRefresh = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? refreshToken
        let body = "grant_type=refresh_token"
            + "&client_id=\(Constants.codexOAuthClientID)"
            + "&refresh_token=\(encodedRefresh)"
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw CodexError.invalidResponse }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw CodexError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else { return nil }

        struct RefreshResponse: Decodable {
            let accessToken: String?
            enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
        }
        let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data)
        return decoded?.accessToken
    }

    // MARK: - Usage request

    private func performRequest(accessToken: String, accountID: String?) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Constants.codexUsageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: Constants.codexAccountIDHeader)
        }
        request.timeoutInterval = Constants.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw CodexError.invalidResponse }

        switch http.statusCode {
        case 200:
            return try parse(data: data, http: http)
        case 401, 403:
            throw CodexError.unauthorized
        case 503:
            throw CodexError.serviceUnavailable
        default:
            throw CodexError.serverError(http.statusCode)
        }
    }

    // MARK: - Parsing

    private struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let rateLimitResetCredits: ResetCreditsSummary?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case rateLimitResetCredits = "rate_limit_reset_credits"
        }
    }

    private struct ResetCreditsSummary: Decodable {
        let availableCount: Int
        enum CodingKeys: String, CodingKey { case availableCount = "available_count" }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let resetAt: Double?
        let resetAfterSeconds: Double?
        let limitWindowSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case resetAfterSeconds = "reset_after_seconds"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    private func parse(data: Data, http: HTTPURLResponse) throws -> ProviderUsageSnapshot {
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        let currentDate = now()

        let headerPrimary = headerPercent(http, Constants.codexPrimaryUsedPercentHeader)
        let headerSecondary = headerPercent(http, Constants.codexSecondaryUsedPercentHeader)

        var windows: [UsageWindow] = []
        if let primary = makeWindow(
            decoded.rateLimit?.primaryWindow,
            overridePercent: headerPrimary,
            fallbackType: .codexFiveHour,
            now: currentDate
        ) {
            windows.append(primary)
        }
        if let secondary = makeWindow(
            decoded.rateLimit?.secondaryWindow,
            overridePercent: headerSecondary,
            fallbackType: .codexWeekly,
            now: currentDate
        ) {
            windows.append(secondary)
        }

        guard !windows.isEmpty else { throw CodexError.invalidResponse }

        let resetCredits = decoded.rateLimitResetCredits.map {
            RateLimitResetCredits(availableCount: $0.availableCount, expirations: [])
        }

        return ProviderUsageSnapshot(
            provider: .codex,
            windows: windows,
            planName: planName(from: decoded.planType),
            rateLimitResetCredits: resetCredits,
            fetchedAt: currentDate
        )
    }

    /// Builds a window from the server's live `used_percent`. The server value is
    /// authoritative even if `reset_at` is slightly past — no zero-on-expiry
    /// fabrication (that was the original bug).
    private func makeWindow(
        _ window: Window?,
        overridePercent: Double?,
        fallbackType: UsageWindowType,
        now: Date
    ) -> UsageWindow? {
        guard let percent = overridePercent ?? window?.usedPercent else { return nil }
        let type = windowType(for: window?.limitWindowSeconds, fallback: fallbackType)
        let duration = window?.limitWindowSeconds ?? type?.totalDuration ?? fallbackType.totalDuration

        let resetsAt: Date
        if let resetAt = window?.resetAt {
            resetsAt = Date(timeIntervalSince1970: resetAt)
        } else if let after = window?.resetAfterSeconds {
            resetsAt = now.addingTimeInterval(after)
        } else {
            resetsAt = now.addingTimeInterval(duration)
        }

        if let type {
            return UsageWindow(utilization: percent, resetsAt: resetsAt, windowType: type)
        }

        return UsageWindow(
            utilization: percent,
            resetsAt: resetsAt,
            windowID: UsageWindowID(rawValue: "codex-custom-\(fallbackType.rawValue)"),
            displayName: "Usage limit",
            totalDuration: duration
        )
    }

    /// The API's primary/secondary slots are not stable identities: while the
    /// five-hour limit is unavailable, the weekly limit moves into primary.
    /// Duration metadata is authoritative when present. Slot identity remains a
    /// compatibility fallback for older and header-only responses.
    private func windowType(
        for duration: TimeInterval?,
        fallback: UsageWindowType
    ) -> UsageWindowType? {
        guard let duration else { return fallback }
        if duration == UsageWindowType.codexFiveHour.totalDuration {
            return .codexFiveHour
        }
        if duration == UsageWindowType.codexWeekly.totalDuration {
            return .codexWeekly
        }
        return nil
    }

    private func headerPercent(_ http: HTTPURLResponse, _ name: String) -> Double? {
        guard let raw = http.value(forHTTPHeaderField: name) else { return nil }
        return Double(raw)
    }

    private func planName(from planType: String?) -> String? {
        guard let raw = planType?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw.lowercased() {
        case "prolite": return "Pro 5x"
        case "pro": return "Pro 20x"
        default: return raw.capitalized
        }
    }

    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        Constants.initialRetryDelay * pow(Constants.retryBackoffMultiplier, Double(attempt))
    }

    // MARK: - Reset Credits

    /// Enriches a usage snapshot with per-credit expiry details from the dedicated
    /// `/wham/rate-limit-reset-credits` endpoint. Best-effort: on any failure the
    /// snapshot is returned unchanged (keeping the usage-body count as the fallback).
    private func enrichWithResetCredits(
        _ snapshot: ProviderUsageSnapshot,
        accessToken: String,
        accountID: String?
    ) async -> ProviderUsageSnapshot {
        guard let details = await fetchResetCreditsDetails(accessToken: accessToken, accountID: accountID) else {
            return snapshot
        }
        return ProviderUsageSnapshot(
            provider: snapshot.provider,
            windows: snapshot.windows,
            extraUsage: snapshot.extraUsage,
            planName: snapshot.planName,
            rateLimitResetCredits: RateLimitResetCredits(
                availableCount: details.availableCount,
                expirations: details.expirations
            ),
            fetchedAt: snapshot.fetchedAt
        )
    }

    /// Best-effort GET of the dedicated reset-credits endpoint (per-credit expiry).
    /// Never throws — returns nil on any failure so callers fall back to the
    /// usage-body count. Requires extra headers the endpoint expects.
    private func fetchResetCreditsDetails(accessToken: String, accountID: String?) async -> ResetCreditsDetails? {
        var request = URLRequest(url: Constants.codexResetCreditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: Constants.codexAccountIDHeader)
        }
        request.timeoutInterval = Constants.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.codex.info("Reset-credits fetch failed; using usage-body count: \(error.localizedDescription)")
            return nil
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            Logger.codex.info("Reset-credits fetch returned non-2xx; using usage-body count")
            return nil
        }

        return parseResetCreditsDetails(data: data)
    }

    /// Parses the dedicated reset-credits response. Uses `JSONSerialization` to handle
    /// `expires_at` as either an ISO-8601 string or an epoch number.
    private func parseResetCreditsDetails(data: Data) -> ResetCreditsDetails? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let count = (json["available_count"] as? Int)
            ?? (json["available_count"] as? Double).map({ Int($0) }) else { return nil }
        let credits = json["credits"] as? [[String: Any]] ?? []
        let expirations = credits
            .filter { credit in
                guard let status = credit["status"] as? String else { return true }
                return status == "available"
            }
            .compactMap { credit -> Date? in
                if let str = credit["expires_at"] as? String {
                    return codexResetCreditDateFormatterWithFractional.date(from: str)
                        ?? codexResetCreditDateFormatter.date(from: str)
                }
                if let seconds = credit["expires_at"] as? Double {
                    return Date(timeIntervalSince1970: seconds)
                }
                return nil
            }
            .sorted()
        return ResetCreditsDetails(availableCount: count, expirations: expirations)
    }
}

private struct ResetCreditsDetails {
    let availableCount: Int
    let expirations: [Date]
}

private let codexResetCreditDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let codexResetCreditDateFormatterWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private extension CharacterSet {
    /// URL-query value safe set (excludes `&`, `=`, `+`, etc.).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
#endif
