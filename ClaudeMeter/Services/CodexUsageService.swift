//
//  CodexUsageService.swift
//  ClaudeMeter
//
//  Codex (ChatGPT subscription) rate-limit windows from the live usage API.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
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
actor CodexUsageService {
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
                return try await performRequest(accessToken: accessToken, accountID: auth.accountID)
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
                    Logger.codex.info("Codex usage request failed (attempt \(attempt + 1)/\(Constants.maxRetryAttempts)). Retrying in \(String(format: "%.1f", delay))s...")
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
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
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
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
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
        let credits: CreditDetails?
        /// Model-specific limits (e.g. GPT-5.3-Codex-Spark) alongside primary/weekly.
        let additionalRateLimits: [AdditionalRateLimit]?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case credits
            case additionalRateLimits = "additional_rate_limits"
        }
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

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case resetAfterSeconds = "reset_after_seconds"
        }
    }

    /// One entry of `additional_rate_limits`: a named, model-specific limit
    /// (e.g. GPT-5.3-Codex-Spark) whose windows reuse the `RateLimit` shape.
    private struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }

        /// Whether this entry is a Codex Spark limit (by name).
        var isSpark: Bool {
            [limitName, meteredFeature]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains("spark") }
        }

        var displayName: String {
            let label = limitName ?? meteredFeature ?? "Codex extra"
            return label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// `credits` object from `wham/usage`. `balance` is the remaining prepaid
    /// credit in USD (may arrive as a number or a numeric string).
    private struct CreditDetails: Decodable {
        let balance: Double?

        enum CodingKeys: String, CodingKey { case balance }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(Double.self, forKey: .balance) {
                balance = value
            } else if let string = try? container.decode(String.self, forKey: .balance),
                      let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                balance = value
            } else {
                balance = nil
            }
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
            type: .codexFiveHour,
            now: currentDate
        ) {
            windows.append(primary)
        }
        if let secondary = makeWindow(
            decoded.rateLimit?.secondaryWindow,
            overridePercent: headerSecondary,
            type: .codexWeekly,
            now: currentDate
        ) {
            windows.append(secondary)
        }

        // Model-specific limits (e.g. GPT-5.3-Codex-Spark) from `additional_rate_limits`.
        // Ported from CodexBar's CodexAdditionalRateLimitMapper (MIT, © 2026 Peter Steinberger).
        for entry in decoded.additionalRateLimits ?? [] {
            let label = entry.displayName
            if let spark = makeWindow(
                entry.rateLimit?.primaryWindow,
                overridePercent: nil,
                type: .codexSpark,
                now: currentDate,
                name: entry.isSpark ? "Codex Spark" : label
            ) {
                windows.append(spark)
            }
            if let sparkWeekly = makeWindow(
                entry.rateLimit?.secondaryWindow,
                overridePercent: nil,
                type: .codexSparkWeekly,
                now: currentDate,
                name: entry.isSpark ? "Codex Spark weekly" : label
            ) {
                windows.append(sparkWeekly)
            }
        }

        guard !windows.isEmpty else { throw CodexError.invalidResponse }

        return ProviderUsageSnapshot(
            provider: .codex,
            windows: windows,
            planName: planName(from: decoded.planType),
            creditsRemaining: decoded.credits?.balance,
            fetchedAt: currentDate
        )
    }

    /// Builds a window from the server's live `used_percent`. The server value is
    /// authoritative even if `reset_at` is slightly past — no zero-on-expiry
    /// fabrication (that was the original bug).
    private func makeWindow(
        _ window: Window?,
        overridePercent: Double?,
        type: UsageWindowType,
        now: Date,
        name: String? = nil
    ) -> UsageWindow? {
        guard let percent = overridePercent ?? window?.usedPercent else { return nil }

        let resetsAt: Date
        if let resetAt = window?.resetAt {
            resetsAt = Date(timeIntervalSince1970: resetAt)
        } else if let after = window?.resetAfterSeconds {
            resetsAt = now.addingTimeInterval(after)
        } else {
            resetsAt = now.addingTimeInterval(type.totalDuration)
        }

        return UsageWindow(utilization: percent, resetsAt: resetsAt, windowType: type, name: name)
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
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        Constants.initialRetryDelay * pow(Constants.retryBackoffMultiplier, Double(attempt))
    }
}

private extension CharacterSet {
    /// URL-query value safe set (excludes `&`, `=`, `+`, etc.).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
#endif
