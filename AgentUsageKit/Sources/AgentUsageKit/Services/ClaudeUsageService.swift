//
//  ClaudeUsageService.swift
//  AgentUsageKit
//
//  Shared Claude OAuth usage fetch + response parsing.
//
//  This is the single source of truth for turning the Anthropic
//  `/api/oauth/usage` response into a `UsageSnapshot`. Both the main app's
//  `ClaudeAPIService` (which layers retry/backoff on top) and the widget
//  extension's timeline provider (which fetches directly so it can refresh
//  without the app running) call into here so the parsing logic — which
//  evolves as Anthropic adds per-model limits — never drifts between targets.
//

import Foundation
import OSLog

/// Errors surfaced by ``ClaudeUsageService``.
public enum ClaudeUsageError: Error, Sendable {
    case unauthorized
    case invalidResponse
    case serverError(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case networkError(Error)
    /// The endpoint returned no usage data (HTTP 404/204, an empty 200 body, or a
    /// 200 body with no usage windows). This happens after a window reset when no
    /// prompt has been sent yet — genuinely nothing to report, not a failure.
    case noUsageData
}

/// Fetches and parses Claude OAuth usage. Performs a single request (no retry);
/// callers that need retry/backoff wrap this.
public struct ClaudeUsageService: Sendable {
    /// Anthropic OAuth usage endpoint.
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Beta header required by the usage endpoint. Keep in sync with the app's `Constants`.
    public static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.session = session
        self.timeout = timeout
    }

    /// Perform a single usage request and parse the response.
    /// - Parameter token: OAuth access token.
    /// - Throws: ``ClaudeUsageError`` on HTTP/network failure or when there is no usage data.
    public func fetchUsage(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentUsage/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeUsageError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            if data.isEmpty { throw ClaudeUsageError.noUsageData }
            return try Self.parse(data)
        case 204, 404:
            throw ClaudeUsageError.noUsageData
        case 401, 403:
            throw ClaudeUsageError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            throw ClaudeUsageError.rateLimited(retryAfter: retryAfter)
        case 503:
            throw ClaudeUsageError.serviceUnavailable
        default:
            throw ClaudeUsageError.serverError(http.statusCode)
        }
    }

    /// Parse a usage response body into a ``UsageSnapshot``.
    /// - Throws: ``ClaudeUsageError/noUsageData`` when the body carries no usage windows.
    public static func parse(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse.self, from: data)

        // After a window reset with no prompt sent, the endpoint can return a 200
        // body where every window is absent and `limits` is empty. Treat that as
        // "no usage data" rather than fabricating 0% meters.
        let hasAnyWeeklyScoped = (response.limits ?? []).contains { $0.kind == "weekly_scoped" }
        if response.fiveHour == nil,
           response.sevenDay == nil,
           response.sevenDaySonnet == nil,
           response.sevenDayOmelette == nil,
           !hasAnyWeeklyScoped {
            throw ClaudeUsageError.noUsageData
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = response.fiveHour.map {
            UsageWindow(utilization: $0.utilization,
                        resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                        windowType: .session)
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .session)

        // seven_day is the default weekly limit (Opus / all-models).
        let opus = response.sevenDay.map {
            UsageWindow(utilization: $0.utilization,
                        resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                        windowType: .opus)
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)

        let sonnet = response.sevenDaySonnet.map {
            UsageWindow(utilization: $0.utilization,
                        resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                        windowType: .sonnet)
        }

        let design = response.sevenDayOmelette.map {
            UsageWindow(utilization: $0.utilization,
                        resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                        windowType: .design)
        }

        // Fable has no dedicated top-level key; it appears in `limits` as a
        // weekly-scoped entry whose model display name is "Fable".
        let fable = response.limits?
            .first { ($0.scope?.model?.displayName ?? "").caseInsensitiveCompare("Fable") == .orderedSame }
            .map {
                UsageWindow(utilization: $0.percent ?? 0,
                            resetsAt: dateFormatter.date(from: $0.resetsAt ?? "") ?? Date(),
                            windowType: .fable)
            }

        // Extra usage cost (API returns amounts in cents).
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

        return UsageSnapshot(session: session,
                             opus: opus,
                             sonnet: sonnet,
                             design: design,
                             fable: fable,
                             extraUsage: extraUsage,
                             fetchedAt: Date())
    }

    // MARK: - Response DTOs

    private struct APIResponse: Decodable {
        let fiveHour: UsageWindowResponse?
        let sevenDay: UsageWindowResponse?          // Default weekly = Opus limit
        let sevenDaySonnet: UsageWindowResponse?    // Separate Sonnet limit
        let sevenDayOmelette: UsageWindowResponse?  // Claude Design ("omelette" is Anthropic's codename)
        let extraUsage: ExtraUsageResponse?
        let limits: [LimitEntry]?                   // Per-model/session limits (source of Fable, etc.)

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOmelette = "seven_day_omelette"
            case extraUsage = "extra_usage"
            case limits
        }
    }

    private struct LimitEntry: Decodable {
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

    private struct UsageWindowResponse: Decodable {
        let utilization: Double
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct ExtraUsageResponse: Decodable {
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
}
