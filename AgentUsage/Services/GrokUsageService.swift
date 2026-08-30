//
//  GrokUsageService.swift
//  AgentUsage
//
//  SuperGrok / Grok Build rate-limit windows from the CLI billing API.
//

#if os(macOS)
import Foundation
import AgentUsageKit
import OSLog

/// Fetches the current Grok subscription windows from Grok Build's billing API.
///
/// SuperGrok usage is a unified weekly credit pool. Grok Build's `/usage` UI reads
/// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the session
/// token from `~/.grok/auth.json`. That is the same OAuth the CLI already holds
/// (`billing:read`); it is not a grok.com HTML scrape.
///
/// On a 401 the access token is refreshed once via `auth.x.ai/oauth2/token`. The
/// refreshed token is kept in memory only — `auth.json` is owned by Grok Build and
/// is never written back.
actor GrokUsageService: ProviderUsageServiceProtocol {
    nonisolated let provider: Provider = .grok

    enum GrokError: LocalizedError {
        case unauthorized
        case sessionExpired
        case networkError(Error)
        case invalidResponse
        case serviceUnavailable
        case serverError(Int)
        case maxRetriesExceeded

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
                return "Grok session expired. Run `grok login` to sign in again."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Grok billing API."
            case .serviceUnavailable:
                return "Grok billing API temporarily unavailable."
            case .serverError(let code):
                return "Grok billing API error: \(code)"
            case .maxRetriesExceeded:
                return "Failed after multiple retry attempts."
            }
        }
    }

    private struct GrokAuth {
        var accessToken: String
        let refreshToken: String?
        let clientID: String?
    }

    private let session: URLSession
    private let authFileURLs: [URL]
    private let versionFileURLs: [URL]
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        authFileURLs: [URL] = Constants.grokAuthFileURLs,
        versionFileURLs: [URL] = Constants.grokVersionFileURLs,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.authFileURLs = authFileURLs
        self.versionFileURLs = versionFileURLs
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let auth = loadAuth() else {
            Logger.grok.info("No Grok auth.json found; skipping live usage fetch")
            return nil
        }

        var accessToken = auth.accessToken
        var didRefresh = false
        var lastError: GrokError?

        for attempt in 0..<Constants.maxRetryAttempts {
            do {
                return try await performRequest(accessToken: accessToken)
            } catch let error as GrokError {
                lastError = error

                if case .unauthorized = error {
                    guard !didRefresh, let refreshToken = auth.refreshToken else {
                        Logger.grok.error("Grok usage unauthorized; re-auth required")
                        return nil
                    }
                    didRefresh = true
                    do {
                        guard let refreshed = try await refreshAccessToken(
                            refreshToken,
                            clientID: auth.clientID
                        ) else {
                            return nil
                        }
                        accessToken = refreshed
                        continue
                    } catch {
                        Logger.grok.error("Grok token refresh failed; re-auth required")
                        return nil
                    }
                }

                guard error.isRetryable else { throw error }

                if attempt < Constants.maxRetryAttempts - 1 {
                    let delay = min(
                        Constants.initialRetryDelay * pow(Constants.retryBackoffMultiplier, Double(attempt)),
                        Constants.maxRetryDelay
                    )
                    Logger.grok.info(
                        "Grok usage request failed (attempt \(attempt + 1)/\(Constants.maxRetryAttempts)). Retrying..."
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Logger.grok.error("Grok usage request failed after \(Constants.maxRetryAttempts) attempts")
        throw lastError ?? GrokError.maxRetriesExceeded
    }

    // MARK: - Auth

    private func loadAuth() -> GrokAuth? {
        for url in authFileURLs {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            if let direct = auth(from: json) {
                return GrokAuth(
                    accessToken: direct.accessToken,
                    refreshToken: direct.refreshToken,
                    clientID: direct.clientID
                )
            }

            guard let entries = json as? [String: Any] else { continue }
            let candidates = entries.values.compactMap { auth(from: $0) }
            if let preferred = candidates.max(by: { lhs, rhs in
                (lhs.createTime ?? .distantPast) < (rhs.createTime ?? .distantPast)
            }) {
                return GrokAuth(
                    accessToken: preferred.accessToken,
                    refreshToken: preferred.refreshToken,
                    clientID: preferred.clientID
                )
            }
        }
        return nil
    }

    private struct ParsedAuth {
        let accessToken: String
        let refreshToken: String?
        let clientID: String?
        let createTime: Date?
    }

    private func auth(from json: Any) -> ParsedAuth? {
        Self.auth(from: json)
    }

    private static func auth(from json: Any) -> ParsedAuth? {
        guard let object = json as? [String: Any] else { return nil }
        let token = string(object["key"]) ?? string(object["access_token"])
        guard let token, !token.isEmpty else { return nil }
        let createTime = string(object["create_time"]).flatMap(parseISODate)
        return ParsedAuth(
            accessToken: token,
            refreshToken: string(object["refresh_token"]),
            clientID: string(object["oidc_client_id"]),
            createTime: createTime
        )
    }

    private func refreshAccessToken(_ refreshToken: String, clientID: String?) async throws -> String? {
        var request = URLRequest(url: Constants.grokTokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Constants.requestTimeout

        var parts = [
            "grant_type=refresh_token",
            "refresh_token=\(urlEncoded(refreshToken))",
        ]
        if let clientID, !clientID.isEmpty {
            parts.append("client_id=\(urlEncoded(clientID))")
        }
        request.httpBody = parts.joined(separator: "&").data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GrokError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw GrokError.invalidResponse }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw GrokError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else { return nil }

        struct RefreshResponse: Decodable {
            let accessToken: String?
            enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
        }
        return try? JSONDecoder().decode(RefreshResponse.self, from: data).accessToken
    }

    // MARK: - Usage request

    private func performRequest(accessToken: String) async throws -> ProviderUsageSnapshot {
        async let credits = fetchJSON(url: Constants.grokBillingCreditsURL, accessToken: accessToken)
        async let fallback = fetchJSON(url: Constants.grokBillingURL, accessToken: accessToken)
        let (creditsResult, fallbackResult) = try await (credits, fallback)

        if creditsResult.status == 401 || fallbackResult.status == 401 {
            throw GrokError.unauthorized
        }
        if creditsResult.status == 503 || fallbackResult.status == 503 {
            throw GrokError.serviceUnavailable
        }

        let currentDate = now()
        if let snapshot = Self.mapBilling(
            creditsBody: creditsResult.object,
            fallbackBody: fallbackResult.object,
            now: currentDate
        ) {
            return snapshot
        }

        if (200..<300).contains(creditsResult.status) || (200..<300).contains(fallbackResult.status) {
            throw GrokError.invalidResponse
        }
        throw GrokError.serverError(max(creditsResult.status, fallbackResult.status))
    }

    private struct JSONResponse {
        let status: Int
        let object: [String: Any]?
    }

    private func fetchJSON(url: URL, accessToken: String) async throws -> JSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(Constants.grokClientSurface, forHTTPHeaderField: Constants.grokClientSurfaceHeader)
        request.setValue(clientVersion(), forHTTPHeaderField: Constants.grokClientVersionHeader)
        request.timeoutInterval = Constants.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GrokError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw GrokError.invalidResponse }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return JSONResponse(status: http.statusCode, object: object)
    }

    private func clientVersion() -> String {
        for url in versionFileURLs {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = Self.string(json["version"]),
                  !version.isEmpty else {
                continue
            }
            return version
        }
        return Constants.grokClientVersionFallback
    }

    // MARK: - Mapping

    /// Maps Grok Build billing JSON into a provider snapshot.
    ///
    /// `format=credits` carries the SuperGrok weekly pool (`creditUsagePercent` +
    /// `currentPeriod`). A fresh period omits the percent entirely — treat that as 0.
    /// On-demand spend maps to `extraUsage` when a cap is set.
    nonisolated static func mapBilling(
        creditsBody: [String: Any]?,
        fallbackBody: [String: Any]?,
        now: Date
    ) -> ProviderUsageSnapshot? {
        let creditsConfig = config(from: creditsBody)
        let fallbackConfig = config(from: fallbackBody)
        var windows: [UsageWindow] = []

        if let weekly = weeklyWindow(from: creditsConfig ?? fallbackConfig, now: now) {
            windows.append(weekly)
        }

        if windows.isEmpty, let monthly = monthlyWindow(
            from: fallbackConfig ?? creditsConfig,
            now: now
        ) {
            windows.append(monthly)
        }

        let extraUsage = extraUsageCost(from: creditsConfig, fallback: fallbackConfig)
        let planName = planName(from: creditsBody)
            ?? planName(from: fallbackBody)
            ?? planName(from: creditsConfig)
            ?? planName(from: fallbackConfig)

        guard !windows.isEmpty || extraUsage != nil else { return nil }

        return ProviderUsageSnapshot(
            provider: .grok,
            windows: windows,
            extraUsage: extraUsage,
            planName: planName,
            fetchedAt: now
        )
    }

    private nonisolated static func weeklyWindow(
        from config: [String: Any]?,
        now: Date
    ) -> UsageWindow? {
        guard let config else { return nil }
        let period = dictionary(config["currentPeriod"]) ?? dictionary(config["current_period"])
        let periodType = (string(period?["type"]) ?? "").uppercased()
        let percent = number(config["creditUsagePercent"])
            ?? number(config["credit_usage_percent"])
        let isWeeklyPeriod = periodType.contains("WEEKLY")
        guard isWeeklyPeriod || (period == nil && percent != nil) else { return nil }

        let start = date(period?["start"])
            ?? date(config["billingPeriodStart"])
            ?? date(config["billing_period_start"])
        let end = date(period?["end"])
            ?? date(config["billingPeriodEnd"])
            ?? date(config["billing_period_end"])
            ?? now.addingTimeInterval(UsageWindowType.grokWeekly.totalDuration)

        let duration: TimeInterval
        if let start {
            duration = max(end.timeIntervalSince(start), UsageWindowType.grokWeekly.totalDuration)
        } else {
            duration = UsageWindowType.grokWeekly.totalDuration
        }

        return UsageWindow(
            utilization: percent ?? 0,
            resetsAt: end,
            windowType: .grokWeekly
        ).withDuration(duration)
    }

    private nonisolated static func monthlyWindow(
        from config: [String: Any]?,
        now: Date
    ) -> UsageWindow? {
        guard let config,
              let limit = cents(config["monthlyLimit"]) ?? cents(config["monthly_limit"]),
              limit > 0 else {
            return nil
        }
        let used = cents(config["used"]) ?? cents(config["includedUsed"]) ?? 0
        let end = date(config["billingPeriodEnd"])
            ?? date(config["billing_period_end"])
            ?? now.addingTimeInterval(UsageWindowType.openCodeGoMonthly.totalDuration)
        let start = date(config["billingPeriodStart"])
            ?? date(config["billing_period_start"])
        let duration = start.map { end.timeIntervalSince($0) }
            ?? UsageWindowType.openCodeGoMonthly.totalDuration

        return UsageWindow(
            utilization: (used / limit) * 100,
            resetsAt: end,
            windowID: UsageWindowID(rawValue: "grok.monthly"),
            displayName: "Monthly limit",
            totalDuration: max(duration, 0)
        )
    }

    private nonisolated static func extraUsageCost(
        from credits: [String: Any]?,
        fallback: [String: Any]?
    ) -> ExtraUsageCost? {
        let cap = cents(credits?["onDemandCap"])
            ?? cents(credits?["on_demand_cap"])
            ?? cents(fallback?["onDemandCap"])
            ?? cents(fallback?["on_demand_cap"])
            ?? 0
        guard cap > 0 else { return nil }
        let used = cents(credits?["onDemandUsed"])
            ?? cents(credits?["on_demand_used"])
            ?? cents(fallback?["onDemandUsed"])
            ?? cents(fallback?["on_demand_used"])
            ?? 0
        return ExtraUsageCost(used: used, limit: cap, currencyCode: "USD")
    }

    private nonisolated static func planName(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let raw = string(object["subscriptionTier"])
            ?? string(object["subscription_tier"])
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    private nonisolated static func config(from body: [String: Any]?) -> [String: Any]? {
        guard let body else { return nil }
        return dictionary(body["config"]) ?? body
    }

    private nonisolated static func cents(_ value: Any?) -> Double? {
        if let wrapped = dictionary(value), let inner = wrapped["val"] {
            return cents(inner)
        }
        guard let units = number(value) else { return nil }
        return units / 100.0
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    private nonisolated static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private nonisolated static func date(_ value: Any?) -> Date? {
        if let string = string(value) { return parseISODate(string) }
        if let seconds = number(value) {
            let epoch = seconds > 10_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    private nonisolated static func parseISODate(_ raw: String) -> Date? {
        let candidates = [raw, raw.replacingOccurrences(of: "+00:00", with: "Z")]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        for candidate in candidates {
            if let date = fractional.date(from: candidate) ?? basic.date(from: candidate) {
                return date
            }
        }
        return nil
    }

    private func urlEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
    }
}

private extension UsageWindow {
    func withDuration(_ duration: TimeInterval) -> UsageWindow {
        UsageWindow(
            utilization: utilization,
            resetsAt: resetsAt,
            windowID: windowID,
            displayName: displayName,
            totalDuration: duration,
            scope: scope
        )
    }
}

private nonisolated extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
#endif
