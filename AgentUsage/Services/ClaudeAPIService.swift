//
//  ClaudeAPIService.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit
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
            case .rateLimited(let retryAfter):
                // A Retry-After beyond the in-loop sleep cap means retrying early just adds
                // requests the server already refused; leave it to the view model's cooldown.
                return (retryAfter ?? 0) <= Constants.maxRetryDelay
            case .networkError, .serviceUnavailable:
                return true
            case .serverError(let code):
                // Retry on 5xx server errors (except 501 Not Implemented)
                return code >= 500 && code != 501
            case .unauthorized, .invalidResponse, .maxRetriesExceeded, .noUsageData:
                return false
            }
        }
    }

    /// `ISO8601DateFormatter` treats `.withFractionalSeconds` as *required*, so a
    /// formatter configured for it rejects `2026-07-25T10:00:00Z`. The usage endpoint
    /// normally sends fractional seconds, but a response without them would otherwise
    /// fall back to `Date()` and render every window as already reset.
    /// Instance-held rather than `static`: a `static let` is global storage even inside
    /// an actor, and `ISO8601DateFormatter` is not `Sendable`. As instance state it is
    /// confined to this actor, which is safe under the Swift 6 language mode.
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let wholeSecondTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return fractionalTimestampFormatter.date(from: value)
            ?? wholeSecondTimestampFormatter.date(from: value)
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
        // `cedar_ember` (banked limit resets) is only served to the Claude Code CLI
        // surface; any other User-Agent comes back `eligible: false`.
        request.setValue("claude-cli/\(Self.claudeCodeVersion()) (external, cli)", forHTTPHeaderField: "User-Agent")
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
            Logger.api.warning("Usage endpoint returned 429 (Retry-After: \(retryAfter.map { String(format: "%.0fs", $0) } ?? "none", privacy: .public))")
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 503:
            throw APIError.serviceUnavailable
        default:
            Logger.api.error("Usage endpoint returned unexpected status \(httpResponse.statusCode)")
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Calculate retry delay with exponential backoff, capped at `Constants.maxRetryDelay`.
    private func calculateRetryDelay(attempt: Int, error: APIError) -> TimeInterval {
        // For rate limiting, use Retry-After header if available
        if case .rateLimited(let retryAfter) = error, let seconds = retryAfter {
            return min(seconds, Constants.maxRetryDelay)
        }

        // Exponential backoff: 1s, 2s, 4s, etc.
        let baseDelay = Constants.initialRetryDelay
        let multiplier = pow(Constants.retryBackoffMultiplier, Double(attempt))
        return min(baseDelay * multiplier, Constants.maxRetryDelay)
    }

    /// Parses the `/api/oauth/usage` body. Internal rather than private so tests run
    /// the real parser against captured responses.
    func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        // Debug: Log raw API response to see all available fields
        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            Logger.api.debug("Claude API Response:\n\(prettyString)")
        }
        #endif

        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        let limits = response.limits ?? []

        // After a usage-window reset with no prompt sent yet, the endpoint can
        // return a 200 body where every window is absent/null and `limits` is
        // empty or missing. That is "no usage data" — throw so the ViewModel
        // shows a "No usage data" state instead of fabricating 0% meters.
        // Partial responses (some windows present) fall through and parse
        // normally; absent top-level windows still default to 0% there.
        let hasAnyWeeklyScoped = limits.contains { $0.kind == "weekly_scoped" }
        if Self.primaryWindowKeys.allSatisfy({ response.windows[$0]?.utilization == nil }),
           !hasAnyWeeklyScoped {
            Logger.api.info("Usage response has no windows — no usage data yet (window reset, no prompt sent)")
            throw APIError.noUsageData
        }

        // `limits[]` is the server's own list of meters: classify on `kind`, label from
        // `scope`, and take its `severity`. Rows that match a fixed window are consumed
        // here; whatever is left becomes an additional window.
        var scopedRows = limits.filter { $0.kind != "session" && $0.kind != "weekly_all" }
        func takeScopedRow(named name: String) -> LimitEntry? {
            guard let index = scopedRows.firstIndex(where: {
                ($0.label ?? "").caseInsensitiveCompare(name) == .orderedSame
            }) else { return nil }
            return scopedRows.remove(at: index)
        }

        func window(_ key: String, as type: UsageWindowType) -> UsageWindow? {
            guard let entry = response.windows[key], let utilization = entry.utilization else { return nil }
            return UsageWindow(
                utilization: utilization,
                resetsAt: parseTimestamp(entry.resetsAt) ?? Date(),
                windowType: type
            ).with(budget: entry.budget, lockedReason: entry.lockedReason)
        }

        func window(_ row: LimitEntry, as type: UsageWindowType) -> UsageWindow {
            UsageWindow(
                utilization: row.percent ?? 0,
                resetsAt: parseTimestamp(row.resetsAt) ?? Date(),
                windowType: type
            ).with(serverStatus: row.status)
        }

        /// A fixed window from its top-level key, falling back to its `limits[]` row.
        func window(_ key: String, row: LimitEntry?, as type: UsageWindowType) -> UsageWindow? {
            guard let top = window(key, as: type) else { return row.map { window($0, as: type) } }
            return top.with(serverStatus: row?.status)
        }

        let sessionRow = limits.first { $0.kind == "session" }
        let weeklyRow = limits.first { $0.kind == "weekly_all" }
        let session = window("five_hour", row: sessionRow, as: .session)
            ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .session)
        // seven_day is the default weekly limit ("All models")
        let opus = window("seven_day", row: weeklyRow, as: .opus)
            ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)
        let sonnet = window("seven_day_sonnet", row: takeScopedRow(named: "Sonnet"), as: .sonnet)
        let design = window("seven_day_omelette", row: takeScopedRow(named: "Claude Design"), as: .design)
        // Fable has no dedicated top-level key; it only appears as a weekly-scoped row.
        let fable = takeScopedRow(named: "Fable").map { window($0, as: .fable) }

        var additional: [UsageWindow] = scopedRows.map { row in
            let label = row.label ?? row.kind.map(Self.humanized) ?? "Usage"
            let duration: TimeInterval = switch row.group {
            case "session": UsageWindowType.session.totalDuration
            case "weekly": UsageWindowType.opus.totalDuration
            default: 0
            }
            return UsageWindow(
                utilization: row.percent ?? 0,
                resetsAt: parseTimestamp(row.resetsAt) ?? .distantFuture,
                windowID: UsageWindowID(rawValue: "claude.limit.\(row.kind ?? "row").\(Self.slug(label))"),
                displayName: label,
                totalDuration: duration,
                scope: row.scope?.model?.displayName.map { UsageWindowScope(model: $0) },
                serverStatus: row.status
            )
        }

        // Remaining top-level windows: known keys first, then unrecognised codenames
        // (sorted, since JSON key order is lost) so a new server meter still shows up.
        let extraKeys = Self.knownExtraWindows.map(\.key).filter { response.windows[$0] != nil }
            + response.windows.keys
                .filter { key in
                    !Self.primaryWindowKeys.contains(key) && !Self.knownExtraWindows.contains { $0.key == key }
                }
                .sorted()
        for key in extraKeys {
            guard let entry = response.windows[key] else { continue }
            let budget = entry.budget
            guard let utilization = entry.utilization ?? budget?.percentUsed else { continue }
            // Null placeholders (0%, no reset date, no budget) carry nothing to show.
            if entry.resetsAt == nil, utilization == 0, budget == nil { continue }
            let known = Self.knownExtraWindows.first { $0.key == key }
            let name = known?.name ?? (budget != nil ? "Usage credit" : "Additional limit")
            guard !additional.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            additional.append(UsageWindow(
                utilization: utilization,
                resetsAt: parseTimestamp(entry.resetsAt) ?? .distantFuture,
                windowID: UsageWindowID(rawValue: "claude.\(key)"),
                displayName: name,
                totalDuration: known?.duration ?? 0,
                budget: budget,
                isOneTime: known?.isOneTime ?? false,
                lockedReason: entry.lockedReason
            ))
        }

        let breakdown = (response.sevenDayBreakdown?.rows ?? []).compactMap { row -> UsageShare? in
            guard let key = row.key, let percent = row.percent else { return nil }
            return UsageShare(key: key, displayName: row.displayName ?? Self.humanized(key), percent: percent)
        }

        return UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: sonnet,
            design: design,
            fable: fable,
            extraUsage: response.extraUsage?.cost ?? response.spend?.cost,
            rateLimitResetCredits: response.cedarEmber.flatMap { Self.resetCredits(from: $0, now: Date()) },
            additionalWindows: additional,
            weeklyBreakdown: breakdown,
            fetchedAt: Date()
        )
    }
}

extension ClaudeAPIService {
    /// Installed Claude Code version, read from the `version` each running CLI
    /// session records in `~/.claude/sessions/*.json` (inside the granted folder).
    /// The highest version wins; falls back when no session file is readable.
    nonisolated static func claudeCodeVersion(
        sessionsDirectory: URL? = nil
    ) -> String {
        #if os(macOS)
        let directory = sessionsDirectory ?? Constants.claudeHomeDirectory.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let versions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> String? in
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = json["version"] as? String,
                      !version.isEmpty else { return nil }
                return version
            }
        if let latest = versions.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) {
            return latest
        }
        #endif
        return Constants.claudeCodeVersionFallback
    }
}

extension ClaudeAPIService {
    /// Banked "reset your limits" grants (claude.ai → Settings → Usage → Resets),
    /// returned under `cedar_ember` when the usage endpoint is asked with `cedar_ember=1`.
    nonisolated struct CedarEmberResponse: Decodable {
        let grants: [Grant]?
        let cooldownUntil: String?

        enum CodingKeys: String, CodingKey {
            case grants
            case cooldownUntil = "cooldown_until"
        }

        struct Grant: Decodable {
            let label: String?
            let resetsLeft: Int?
            let endsAt: String?
            let paused: Bool?

            enum CodingKeys: String, CodingKey {
                case label
                case resetsLeft = "resets_left"
                case endsAt = "ends_at"
                case paused
            }
        }
    }

    /// One credit per reset left in each live grant, each expiring at its grant's
    /// `ends_at`. Paused, spent and expired grants bank nothing. nil when nothing is banked.
    nonisolated static func resetCredits(from response: CedarEmberResponse, now: Date) -> RateLimitResetCredits? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSecondFormatter = ISO8601DateFormatter()

        var count = 0
        var expirations: [Date] = []
        var labels: [String] = []
        for grant in response.grants ?? [] {
            let left = max(0, grant.resetsLeft ?? 0)
            guard left > 0, grant.paused != true else { continue }
            let endsAt = grant.endsAt.flatMap { formatter.date(from: $0) ?? wholeSecondFormatter.date(from: $0) }
            if let endsAt, endsAt <= now { continue }
            count += left
            if let endsAt {
                expirations.append(contentsOf: repeatElement(endsAt, count: left))
            }
            if let label = grant.label, !label.isEmpty {
                labels.append(label)
            }
        }
        guard count > 0 else { return nil }
        let cooldownUntil = response.cooldownUntil.flatMap { formatter.date(from: $0) ?? wholeSecondFormatter.date(from: $0) }
        return RateLimitResetCredits(
            availableCount: count,
            expirations: expirations.sorted(),
            grantLabels: labels,
            cooldownUntil: cooldownUntil
        )
    }
}

extension ClaudeAPIService {
    /// Top-level keys that feed the fixed `UsageSnapshot` windows.
    nonisolated static let primaryWindowKeys = ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_omelette"]

    /// Other top-level windows with a known meaning, in display order. Labels follow
    /// Claude Code's `/usage` screen where it has one (`cinder_cove`).
    nonisolated static let knownExtraWindows: [(key: String, name: String, duration: TimeInterval, isOneTime: Bool)] = [
        ("seven_day_opus", "Opus", UsageWindowType.opus.totalDuration, false),
        ("seven_day_cowork", "Cowork", UsageWindowType.opus.totalDuration, false),
        ("seven_day_oauth_apps", "OAuth apps", UsageWindowType.opus.totalDuration, false),
        ("cinder_cove", "Claude Code and Cowork credit", 0, true),
        ("omelette_promotional", "Claude Design promotion", 0, true),
    ]

    /// `seven_day_oauth_apps` → "Seven day oauth apps"; fallback label for unlabelled server data.
    nonisolated static func humanized(_ key: String) -> String {
        let words = key.split(separator: "_").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    nonisolated static func slug(_ label: String) -> String {
        String(label.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    /// The usage endpoint body. Each section decodes leniently so one malformed or
    /// renamed block doesn't discard the rest of the response.
    nonisolated struct UsageResponse: Decodable {
        /// Every top-level object carrying a `utilization` key, by field name
        /// (`five_hour`, `seven_day_opus`, `cinder_cove`, `iguana_necktie`, …).
        let windows: [String: WindowResponse]
        let extraUsage: ExtraUsageResponse?
        let spend: SpendResponse?
        let limits: [LimitEntry]?
        let cedarEmber: CedarEmberResponse?  // Banked limit resets; present only with `cedar_ember=1`
        let sevenDayBreakdown: BreakdownResponse?

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            func section<T: Decodable>(_ key: String) -> T? {
                (try? container.decodeIfPresent(T.self, forKey: Key(stringValue: key))) ?? nil
            }
            var windows: [String: WindowResponse] = [:]
            // `extra_usage` also has a `utilization` key but is the overage block, not a window.
            for key in container.allKeys where key.stringValue != "extra_usage" {
                if let window = try? container.decode(WindowResponse.self, forKey: key) {
                    windows[key.stringValue] = window
                }
            }
            self.windows = windows
            extraUsage = section("extra_usage")
            spend = section("spend")
            limits = section("limits")
            cedarEmber = section("cedar_ember")
            sevenDayBreakdown = section("seven_day_breakdown")
        }
    }

    nonisolated struct WindowResponse: Decodable {
        let utilization: Double?
        let resetsAt: String?
        let limitDollars: Double?
        let usedDollars: Double?
        let remainingDollars: Double?
        let lockedReason: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
            case limitDollars = "limit_dollars"
            case usedDollars = "used_dollars"
            case remainingDollars = "remaining_dollars"
            case lockedReason = "locked_reason"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.utilization) else {
                throw DecodingError.keyNotFound(CodingKeys.utilization, .init(codingPath: decoder.codingPath, debugDescription: "Not a usage window"))
            }
            utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
            resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
            limitDollars = try container.decodeIfPresent(Double.self, forKey: .limitDollars)
            usedDollars = try container.decodeIfPresent(Double.self, forKey: .usedDollars)
            remainingDollars = try container.decodeIfPresent(Double.self, forKey: .remainingDollars)
            lockedReason = try container.decodeIfPresent(String.self, forKey: .lockedReason)
        }

        /// Dollar budget, when the window is denominated in dollars (e.g. a usage credit).
        var budget: ExtraUsageCost? {
            guard let limit = limitDollars, limit > 0 else { return nil }
            let used = usedDollars
                ?? remainingDollars.map { limit - $0 }
                ?? utilization.map { limit * $0 / 100 }
                ?? 0
            return ExtraUsageCost(used: used, limit: limit, currencyCode: "USD")
        }
    }

    /// Generalized limit entry from the `limits` array. Per-model weekly limits
    /// (Fable, etc.) arrive here as `kind == "weekly_scoped"` with the model's
    /// display name under `scope.model.display_name`, rather than as a dedicated
    /// top-level `seven_day_*` key; surface-scoped rows use `scope.surface`.
    nonisolated struct LimitEntry: Decodable {
        let kind: String?
        let group: String?
        let percent: Double?
        let resetsAt: String?
        let severity: String?
        let scope: Scope?

        struct Scope: Decodable {
            let model: Named?
            let surface: Named?
        }

        struct Named: Decodable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case group
            case percent
            case resetsAt = "resets_at"
            case severity
            case scope
        }

        /// The server's display label for a scoped row.
        var label: String? {
            scope?.model?.displayName ?? scope?.surface?.displayName
        }

        var status: UsageStatus? {
            switch severity {
            case "normal": .onTrack
            case "warning": .warning
            case "critical": .critical
            default: nil
            }
        }
    }

    nonisolated struct ExtraUsageResponse: Decodable {
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

        /// Monthly extra usage spend. The API returns amounts in cents.
        var cost: ExtraUsageCost? {
            guard isEnabled == true, let used = usedCredits, let limit = monthlyLimit else { return nil }
            let code = currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExtraUsageCost(used: used / 100.0, limit: limit / 100.0, currencyCode: code?.isEmpty == false ? code! : "USD")
        }
    }

    /// Newer money-typed view of extra usage; used when `extra_usage` has no spend to show.
    nonisolated struct SpendResponse: Decodable {
        let enabled: Bool?
        let used: Money?
        let limit: Money?

        struct Money: Decodable {
            let amountMinor: Double?
            let currency: String?
            let exponent: Int?

            enum CodingKeys: String, CodingKey {
                case amountMinor = "amount_minor"
                case currency
                case exponent
            }

            var major: Double? {
                amountMinor.map { $0 / pow(10, Double(exponent ?? 2)) }
            }
        }

        var cost: ExtraUsageCost? {
            guard enabled == true, let used = used?.major, let limit = limit?.major else { return nil }
            return ExtraUsageCost(used: used, limit: limit, currencyCode: self.used?.currency ?? "USD")
        }
    }

    nonisolated struct BreakdownResponse: Decodable {
        let rows: [Row]?

        struct Row: Decodable {
            let key: String?
            let displayName: String?
            let percent: Double?

            enum CodingKeys: String, CodingKey {
                case key
                case displayName = "display_name"
                case percent
            }
        }
    }
}

extension ClaudeAPIService {
    /// Bridges Claude's richer `UsageSnapshot` into the provider-neutral shape.
    nonisolated static func providerSnapshot(
        from snapshot: UsageSnapshot,
        planName: String? = nil,
        effortSummaries: [EffortPeriodSummary] = [],
        lastUsedAt: Date? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            claude: snapshot,
            planName: planName,
            effortSummaries: effortSummaries,
            lastUsedAt: lastUsedAt
        )
    }
}
