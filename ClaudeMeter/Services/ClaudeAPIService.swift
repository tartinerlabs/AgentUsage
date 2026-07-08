//
//  ClaudeAPIService.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit
import OSLog

actor ClaudeAPIService: APIServiceProtocol {
    enum APIError: LocalizedError {
        case unauthorized
        case networkError(Error)
        case invalidResponse
        case serverError(Int)
        case rateLimited(retryAfter: TimeInterval?)
        case serviceUnavailable
        case maxRetriesExceeded
        /// The usage endpoint returned no usage data (HTTP 404/204, or a 200 body
        /// with no windows). This happens after a usage-window reset when no
        /// prompt has been sent yet — there is genuinely nothing to report.
        /// Not an error: the ViewModel shows a "No usage data" state instead of
        /// holding onto stale cached data.
        case noUsageData

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Unauthorized. Please re-authenticate with Claude CLI."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server."
            case .serverError(let code):
                return "Server error: \(code)"
            case .rateLimited(let retryAfter):
                if let seconds = retryAfter {
                    return "Rate limited. Try again in \(Int(seconds)) seconds."
                }
                return "Rate limited. Please try again later."
            case .serviceUnavailable:
                return "Service temporarily unavailable."
            case .maxRetriesExceeded:
                return "Failed after multiple retry attempts."
            case .noUsageData:
                return nil
            }
        }

        /// Whether this error should trigger a retry
        var isRetryable: Bool {
            switch self {
            case .networkError, .rateLimited, .serviceUnavailable:
                return true
            case .serverError(let code):
                // Retry on 5xx server errors (except 501 Not Implemented)
                return code >= 500 && code != 501
            case .unauthorized, .invalidResponse, .maxRetriesExceeded, .noUsageData:
                return false
            }
        }
    }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        var lastError: APIError?

        for attempt in 0..<Constants.maxRetryAttempts {
            do {
                return try await performRequest(token: token)
            } catch let error as APIError {
                lastError = error

                // Don't retry non-retryable errors
                guard error.isRetryable else {
                    throw error
                }

                // Calculate delay for next retry
                let delay = calculateRetryDelay(attempt: attempt, error: error)

                // Don't wait after the last attempt
                if attempt < Constants.maxRetryAttempts - 1 {
                    Logger.api.info("Request failed (attempt \(attempt + 1)/\(Constants.maxRetryAttempts)): \(error.localizedDescription). Retrying in \(String(format: "%.1f", delay))s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        Logger.api.error("Request failed after \(Constants.maxRetryAttempts) attempts")
        throw lastError ?? APIError.maxRetriesExceeded
    }

    /// Perform a single API request without retry logic
    private func performRequest(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Constants.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Constants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ClaudeMeter/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Constants.requestTimeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            if data.isEmpty {
                Logger.api.info("Usage endpoint returned 200 with empty body — no usage data yet")
                throw APIError.noUsageData
            }
            return try parseUsageResponse(data)
        case 204:
            Logger.api.info("Usage endpoint returned 204 No Content — no usage data yet")
            throw APIError.noUsageData
        case 404:
            // The usage endpoint returns 404 after a window reset when no prompt
            // has been sent yet — there is no usage record to report. This is not
            // a server error; the ViewModel surfaces a "No usage data" state.
            Logger.api.info("Usage endpoint returned 404 — no usage data yet (window reset, no prompt sent)")
            throw APIError.noUsageData
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            // Extract Retry-After header if present
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 503:
            throw APIError.serviceUnavailable
        default:
            Logger.api.error("Usage endpoint returned unexpected status \(httpResponse.statusCode)")
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Calculate retry delay with exponential backoff
    private func calculateRetryDelay(attempt: Int, error: APIError) -> TimeInterval {
        // For rate limiting, use Retry-After header if available
        if case .rateLimited(let retryAfter) = error, let seconds = retryAfter {
            return seconds
        }

        // Exponential backoff: 1s, 2s, 4s, etc.
        let baseDelay = Constants.initialRetryDelay
        let multiplier = pow(Constants.retryBackoffMultiplier, Double(attempt))
        return baseDelay * multiplier
    }

    private func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        // Debug: Log raw API response to see all available fields
        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            Logger.api.debug("Claude API Response:\n\(prettyString)")
        }
        #endif

        struct APIResponse: Decodable {
            let fiveHour: UsageWindowResponse?
            let sevenDay: UsageWindowResponse?        // Default weekly = Opus limit
            let sevenDaySonnet: UsageWindowResponse?  // Separate Sonnet limit
            let sevenDayOmelette: UsageWindowResponse?  // Claude Design ("omelette" is Anthropic's internal codename)
            let extraUsage: ExtraUsageResponse?
            let limits: [LimitEntry]?  // Generalized per-model/session limits (source of Fable, etc.)

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
                case sevenDaySonnet = "seven_day_sonnet"
                case sevenDayOmelette = "seven_day_omelette"
                case extraUsage = "extra_usage"
                case limits
            }
        }

        // Generalized limit entry from the `limits` array. Per-model weekly limits
        // (Fable, etc.) arrive here as `kind == "weekly_scoped"` with the model's
        // display name under `scope.model.display_name`, rather than as a dedicated
        // top-level `seven_day_*` key.
        struct LimitEntry: Decodable {
            let kind: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?

            struct Scope: Decodable {
                let model: Model?

                struct Model: Decodable {
                    let displayName: String?

                    enum CodingKeys: String, CodingKey {
                        case displayName = "display_name"
                    }
                }
            }

            enum CodingKeys: String, CodingKey {
                case kind
                case percent
                case resetsAt = "resets_at"
                case scope
            }
        }

        struct UsageWindowResponse: Decodable {
            let utilization: Double
            let resetsAt: String

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        struct ExtraUsageResponse: Decodable {
            let isEnabled: Bool?
            let monthlyLimit: Double?
            let usedCredits: Double?
            let currency: String?

            enum CodingKeys: String, CodingKey {
                case isEnabled = "is_enabled"
                case monthlyLimit = "monthly_limit"
                case usedCredits = "used_credits"
                case currency
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse.self, from: data)

        // After a usage-window reset with no prompt sent yet, the endpoint can
        // return a 200 body where every window is absent/null and `limits` is
        // empty or missing. That is "no usage data" — throw so the ViewModel
        // shows a "No usage data" state instead of fabricating 0% meters.
        // Partial responses (some windows present) fall through and parse
        // normally; absent top-level windows still default to 0% there.
        let hasAnyWeeklyScoped = (response.limits ?? []).contains { $0.kind == "weekly_scoped" }
        if response.fiveHour == nil,
           response.sevenDay == nil,
           response.sevenDaySonnet == nil,
           response.sevenDayOmelette == nil,
           !hasAnyWeeklyScoped {
            Logger.api.info("Usage response has no windows — no usage data yet (window reset, no prompt sent)")
            throw APIError.noUsageData
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = response.fiveHour.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .session
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .session)

        // seven_day is now the default weekly limit (Opus)
        let opus = response.sevenDay.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .opus
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)

        // Separate Sonnet limit (if available)
        let sonnet = response.sevenDaySonnet.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .sonnet
            )
        }

        // Claude Design limit (if available)
        let design = response.sevenDayOmelette.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .design
            )
        }

        // Separate Fable limit (if available). Fable has no dedicated top-level key;
        // it appears in the `limits` array as a weekly-scoped entry whose model
        // display name is "Fable".
        let fable = response.limits?
            .first { ($0.scope?.model?.displayName ?? "").caseInsensitiveCompare("Fable") == .orderedSame }
            .map {
                UsageWindow(
                    utilization: $0.percent ?? 0,
                    resetsAt: dateFormatter.date(from: $0.resetsAt ?? "") ?? Date(),
                    windowType: .fable
                )
            }

        // Extra usage cost (API returns amounts in cents)
        let extraUsage: ExtraUsageCost? = {
            guard let extra = response.extraUsage,
                  extra.isEnabled == true,
                  let used = extra.usedCredits,
                  let limit = extra.monthlyLimit else {
                return nil
            }
            let currency = extra.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = (currency?.isEmpty ?? true) ? "USD" : currency!
            return ExtraUsageCost(used: used / 100.0, limit: limit / 100.0, currencyCode: code)
        }()

        return UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: sonnet,
            design: design,
            fable: fable,
            extraUsage: extraUsage,
            fetchedAt: Date()
        )
    }
}
