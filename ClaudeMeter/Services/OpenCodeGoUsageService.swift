//
//  OpenCodeGoUsageService.swift
//  ClaudeMeter
//
//  OpenCode quota windows from the opencode.ai server-function JSON RPC.
//
//  Quota logic ported from CodexBar (MIT, © 2026 Peter Steinberger),
//  https://github.com/steipete/CodexBar — specifically the `/_server`
//  JSON RPC approach and the recursive window-hunter parser, replacing
//  the earlier brittle HTML/React-RSC regex scrape.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog

/// Fetches OpenCode rate-limit windows from the authenticated opencode.ai
/// server-function endpoint.
///
/// The earlier implementation scraped the rendered `/workspace/<id>/go` HTML
/// page with a regex tightly coupled to React Server Component serialization;
/// any frontend deploy could silently break quota display (the column just
/// vanished). This port calls the `/_server` JSON RPC that the dashboard itself
/// uses, parses structured JSON first, and only falls back to the regex when
/// the payload is not valid JSON. Auth failures surface as a typed
/// `.invalidCredentials` error instead of a silent `nil`.
actor OpenCodeGoUsageService {
    nonisolated let provider: Provider = .openCode

    enum OpenCodeError: LocalizedError, Equatable {
        /// Cookie is missing, invalid, or expired (401/403 or signed-out body).
        case invalidCredentials
        /// A transport-level network failure.
        case networkError(String)
        /// HTTP 5xx — treated as a service outage so the UI keeps cached data.
        case serverError(Int)
        /// Any other non-2xx HTTP status with its code and a best-effort message.
        case apiError(Int, String)
        /// The response could not be parsed into usage windows.
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "OpenCode session cookie is invalid or expired. Re-authenticate in Settings."
            case .networkError(let message):
                return "OpenCode network error: \(message)"
            case .serverError(let code):
                return "OpenCode dashboard server error (\(code))"
            case .apiError(let code, let message):
                return "OpenCode API error (\(code)): \(message)"
            case .parseFailed(let message):
                return "OpenCode parse error: \(message)"
            }
        }
    }

    // MARK: - Server-function identifiers (ported from CodexBar)

    private nonisolated static let baseURL = URL(string: "https://opencode.ai")!
    private nonisolated static let serverURL = URL(string: "https://opencode.ai/_server")!
    /// Server-function ID for the workspaces list (used to auto-discover the
    /// `wrk_` workspace ID from the authenticated cookie).
    nonisolated static let workspacesServerID =
        "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    /// Server-function ID for the subscription usage payload (rolling/weekly).
    nonisolated static let subscriptionServerID =
        "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"

    private nonisolated static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    // MARK: - Key aliases (ported from CodexBar)

    private nonisolated static let percentKeys = [
        "usagePercent", "usedPercent", "percentUsed", "percent",
        "usage_percent", "used_percent", "utilization", "utilizationPercent",
        "utilization_percent", "usage"
    ]
    private nonisolated static let resetInKeys = [
        "resetInSec", "resetInSeconds", "resetSeconds", "reset_sec",
        "reset_in_sec", "resetsInSec", "resetsInSeconds", "resetIn", "resetSec"
    ]
    private nonisolated static let resetAtKeys = [
        "resetAt", "resetsAt", "reset_at", "resets_at",
        "nextReset", "next_reset", "renewAt", "renew_at"
    ]
    private nonisolated static let renewAtKeys = ["renewAt", "renew_at"]

    private let transport: any OpenCodeHTTPTransport
    private let configProvider: @Sendable () -> DashboardConfig?
    private let now: @Sendable () -> Date

    init(
        transport: any OpenCodeHTTPTransport = OpenCodeURLSessionTransport(),
        configProvider: @escaping @Sendable () -> DashboardConfig? = { DashboardConfig.load() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.configProvider = configProvider
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let config = configProvider() else { return nil }
        let cookieHeader = config.cookieHeader

        let workspaceID: String
        if let override = config.workspaceID {
            workspaceID = override
        } else {
            workspaceID = try await fetchWorkspaceID(cookieHeader: cookieHeader)
        }

        let referer = URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing")
            ?? Self.baseURL
        let text = try await fetchServerText(
            serverID: Self.subscriptionServerID,
            args: [workspaceID],
            method: "GET",
            referer: referer,
            cookieHeader: cookieHeader
        )
        if Self.looksSignedOut(text: text) {
            throw OpenCodeError.invalidCredentials
        }
        if Self.isExplicitNullPayload(text: text) {
            throw OpenCodeError.apiError(200, "No subscription usage data for workspace \(workspaceID).")
        }

        // Retry once via POST if the GET payload lacks usage fields (CodexBar pattern).
        if Self.parseSubscriptionJSON(text: text, now: now()) == nil,
           Self.extractDouble(
               pattern: #"rollingUsage[^}]*?['\"]?usagePercent['\"]?\s*:\s*['\"]?([0-9]+(?:\.[0-9]+)?)['\"]?"#,
               text: text) == nil
        {
            Logger.tokenUsage.warning("OpenCode subscription payload missing after GET; retrying with POST.")
            let fallback = try await fetchServerText(
                serverID: Self.subscriptionServerID,
                args: [workspaceID],
                method: "POST",
                referer: referer,
                cookieHeader: cookieHeader
            )
            if Self.looksSignedOut(text: fallback) {
                throw OpenCodeError.invalidCredentials
            }
            if Self.isExplicitNullPayload(text: fallback) {
                throw OpenCodeError.apiError(200, "No subscription usage data for workspace \(workspaceID).")
            }
            return try Self.parseSubscription(text: fallback, now: now())
        }

        return try Self.parseSubscription(text: text, now: now())
    }

    // MARK: - Workspace auto-discovery

    private func fetchWorkspaceID(cookieHeader: String) async throws -> String {
        let text = try await fetchServerText(
            serverID: Self.workspacesServerID,
            args: nil,
            method: "GET",
            referer: Self.baseURL,
            cookieHeader: cookieHeader
        )
        if Self.looksSignedOut(text: text) {
            throw OpenCodeError.invalidCredentials
        }
        var ids = Self.parseWorkspaceIDs(text: text)
        if ids.isEmpty {
            ids = Self.parseWorkspaceIDsFromJSON(text: text)
        }
        if ids.isEmpty {
            Logger.tokenUsage.warning("OpenCode workspace IDs missing after GET; retrying with POST.")
            let fallback = try await fetchServerText(
                serverID: Self.workspacesServerID,
                args: [],
                method: "POST",
                referer: Self.baseURL,
                cookieHeader: cookieHeader
            )
            if Self.looksSignedOut(text: fallback) {
                throw OpenCodeError.invalidCredentials
            }
            ids = Self.parseWorkspaceIDs(text: fallback)
            if ids.isEmpty {
                ids = Self.parseWorkspaceIDsFromJSON(text: fallback)
            }
        }
        guard let id = ids.first else {
            throw OpenCodeError.parseFailed("Missing workspace id.")
        }
        return id
    }

    // MARK: - Server-function transport

    private func fetchServerText(
        serverID: String,
        args: [Any]?,
        method: String,
        referer: URL,
        cookieHeader: String
    ) async throws -> String {
        let url = Self.serverRequestURL(serverID: serverID, args: args, method: method)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(serverID, forHTTPHeaderField: "X-Server-Id")
        request.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if method.uppercased() != "GET", let args {
            let body = try JSONSerialization.data(withJSONObject: args, options: [])
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.response(for: request)
        } catch let error as URLError where error.code == .badServerResponse {
            throw OpenCodeError.networkError("Invalid response")
        } catch {
            throw OpenCodeError.networkError(error.localizedDescription)
        }

        guard response.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if Self.looksSignedOut(text: bodyText) || response.statusCode == 401 || response.statusCode == 403 {
                throw OpenCodeError.invalidCredentials
            }
            if (500...599).contains(response.statusCode) {
                Logger.tokenUsage.error("OpenCode returned \(response.statusCode)")
                throw OpenCodeError.serverError(response.statusCode)
            }
            if let message = Self.extractServerErrorMessage(from: bodyText) {
                throw OpenCodeError.apiError(response.statusCode, message)
            }
            throw OpenCodeError.apiError(response.statusCode, "")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenCodeError.parseFailed("Response was not UTF-8.")
        }
        return text
    }

    private nonisolated static func serverRequestURL(
        serverID: String,
        args: [Any]?,
        method: String
    ) -> URL {
        guard method.uppercased() == "GET" else { return serverURL }
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "id", value: serverID)]
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args, options: []),
           let encodedArgs = String(data: data, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "args", value: encodedArgs))
        }
        components?.queryItems = queryItems
        return components?.url ?? serverURL
    }

    // MARK: - Parsing (JSON-first, regex fallback)

    nonisolated static func parseSubscription(text: String, now: Date) throws -> ProviderUsageSnapshot {
        if let snapshot = parseSubscriptionJSON(text: text, now: now) {
            return snapshot
        }

        guard let rollingPercent = extractDouble(
                pattern: #"rollingUsage[^}]*?['\"]?usagePercent['\"]?\s*:\s*['\"]?([0-9]+(?:\.[0-9]+)?)['\"]?"#,
                text: text),
              let rollingReset = extractInt(
                pattern: #"rollingUsage[^}]*?['\"]?resetInSec['\"]?\s*:\s*['\"]?([0-9]+)['\"]?"#,
                text: text),
              let weeklyPercent = extractDouble(
                pattern: #"weeklyUsage[^}]*?['\"]?usagePercent['\"]?\s*:\s*['\"]?([0-9]+(?:\.[0-9]+)?)['\"]?"#,
                text: text),
              let weeklyReset = extractInt(
                pattern: #"weeklyUsage[^}]*?['\"]?resetInSec['\"]?\s*:\s*['\"]?([0-9]+)['\"]?"#,
                text: text)
        else {
            throw OpenCodeError.parseFailed("Missing usage fields.")
        }

        let monthlyPercent = extractDouble(
            pattern: #"monthlyUsage[^}]*?['\"]?usagePercent['\"]?\s*:\s*['\"]?([0-9]+(?:\.[0-9]+)?)['\"]?"#,
            text: text)
        let monthlyReset = extractInt(
            pattern: #"monthlyUsage[^}]*?['\"]?resetInSec['\"]?\s*:\s*['\"]?([0-9]+)['\"]?"#,
            text: text)

        return buildSnapshot(
            rollingPercent: rollingPercent, rollingReset: rollingReset,
            weeklyPercent: weeklyPercent, weeklyReset: weeklyReset,
            monthlyPercent: monthlyPercent, monthlyReset: monthlyReset,
            renewsAt: nil, now: now)
    }

    private nonisolated static func parseSubscriptionJSON(text: String, now: Date) -> ProviderUsageSnapshot? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        let renewsAt = dateValue(from: value(from: object as? [String: Any] ?? [:], keys: renewAtKeys))
        if let dict = object as? [String: Any],
           let snapshot = parseUsageDictionary(dict, now: now, inheritedRenewsAt: renewsAt)
        {
            return snapshot
        }
        if let dict = object as? [String: Any] {
            for key in ["data", "result", "usage", "billing", "payload"] {
                if let nested = dict[key] as? [String: Any],
                   let snapshot = parseUsageDictionary(nested, now: now, inheritedRenewsAt: renewsAt)
                {
                    return snapshot
                }
            }
            if let snapshot = parseUsageNested(dict, now: now, depth: 0, inheritedRenewsAt: renewsAt) {
                return snapshot
            }
        }
        return parseUsageFromCandidates(object: object, now: now, inheritedRenewsAt: renewsAt)
    }

    private nonisolated static func parseUsageDictionary(
        _ dict: [String: Any],
        now: Date,
        inheritedRenewsAt: Date?
    ) -> ProviderUsageSnapshot? {
        let renewsAt = dateValue(from: value(from: dict, keys: renewAtKeys)) ?? inheritedRenewsAt
        if let usage = dict["usage"] as? [String: Any],
           let snapshot = parseUsageDictionary(usage, now: now, inheritedRenewsAt: renewsAt)
        {
            return snapshot
        }

        let rollingKeys = ["rollingUsage", "rolling", "rolling_usage", "rollingWindow", "rolling_window"]
        let weeklyKeys = ["weeklyUsage", "weekly", "weekly_usage", "weeklyWindow", "weekly_window"]
        let monthlyKeys = ["monthlyUsage", "monthly", "monthly_usage", "monthlyWindow", "monthly_window"]

        guard let rolling = rollingKeys.compactMap({ dict[$0] as? [String: Any] }).first,
              let weekly = weeklyKeys.compactMap({ dict[$0] as? [String: Any] }).first
        else {
            return nil
        }
        let monthly = monthlyKeys.compactMap({ dict[$0] as? [String: Any] }).first

        return buildSnapshot(
            rolling: rolling, weekly: weekly, monthly: monthly,
            now: now, renewsAt: renewsAt)
    }

    private nonisolated static func parseUsageNested(
        _ dict: [String: Any],
        now: Date,
        depth: Int,
        inheritedRenewsAt: Date?
    ) -> ProviderUsageSnapshot? {
        if depth > 3 { return nil }
        let renewsAt = dateValue(from: value(from: dict, keys: renewAtKeys)) ?? inheritedRenewsAt
        var rolling: [String: Any]?
        var weekly: [String: Any]?
        var monthly: [String: Any]?

        for (key, value) in dict {
            guard let sub = value as? [String: Any] else { continue }
            let lower = key.lowercased()
            if lower.contains("rolling") || lower.contains("hour") || lower.contains("5h") || lower.contains("5-hour") {
                rolling = sub
            } else if lower.contains("weekly") || lower.contains("week") {
                weekly = sub
            } else if lower.contains("monthly") || lower.contains("month") {
                monthly = sub
            }
        }

        if let rolling, let weekly {
            if let snapshot = buildSnapshot(
                rolling: rolling, weekly: weekly, monthly: monthly,
                now: now, renewsAt: renewsAt)
            {
                return snapshot
            }
        }

        for value in dict.values {
            if let sub = value as? [String: Any],
               let snapshot = parseUsageNested(sub, now: now, depth: depth + 1, inheritedRenewsAt: renewsAt)
            {
                return snapshot
            }
        }
        return nil
    }

    private nonisolated static func parseUsageFromCandidates(
        object: Any,
        now: Date,
        inheritedRenewsAt: Date?
    ) -> ProviderUsageSnapshot? {
        var candidates: [WindowCandidate] = []
        collectWindowCandidates(object: object, path: [], out: &candidates)
        guard !candidates.isEmpty else { return nil }

        let rollingCandidates = candidates.filter {
            $0.pathLower.contains("rolling") || $0.pathLower.contains("hour")
                || $0.pathLower.contains("5h") || $0.pathLower.contains("5-hour")
        }
        let weeklyCandidates = candidates.filter {
            $0.pathLower.contains("weekly") || $0.pathLower.contains("week")
        }
        let monthlyCandidates = candidates.filter {
            $0.pathLower.contains("monthly") || $0.pathLower.contains("month")
        }

        let rolling = pickCandidate(preferred: rollingCandidates, fallback: candidates, pickShorter: true)
        let weekly = pickCandidate(
            from: weeklyCandidates.filter { $0.id != rolling?.id }, pickShorter: false)
        let monthly = pickCandidate(
            from: monthlyCandidates.filter { $0.id != rolling?.id && $0.id != weekly?.id },
            pickShorter: false)

        guard let rolling, let weekly else { return nil }

        let renewsAt = dateValue(from: value(from: object as? [String: Any] ?? [:], keys: renewAtKeys))
            ?? inheritedRenewsAt
        return buildSnapshot(
            rollingPercent: rolling.percent, rollingReset: rolling.resetInSec,
            weeklyPercent: weekly.percent, weeklyReset: weekly.resetInSec,
            monthlyPercent: monthly?.percent, monthlyReset: monthly?.resetInSec,
            renewsAt: renewsAt, now: now)
    }

    private struct WindowCandidate {
        let id: UUID
        let percent: Double
        let resetInSec: Int
        let pathLower: String
    }

    private nonisolated static func collectWindowCandidates(
        object: Any,
        path: [String],
        out: inout [WindowCandidate]
    ) {
        if let dict = object as? [String: Any] {
            if let window = parseWindow(dict) {
                out.append(WindowCandidate(
                    id: UUID(), percent: window.percent, resetInSec: window.resetInSec,
                    pathLower: path.joined(separator: ".").lowercased()))
            }
            for (key, value) in dict {
                collectWindowCandidates(object: value, path: path + [key], out: &out)
            }
            return
        }
        if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                collectWindowCandidates(object: value, path: path + ["[\(index)]"], out: &out)
            }
        }
    }

    private nonisolated static func pickCandidate(
        preferred: [WindowCandidate],
        fallback: [WindowCandidate],
        pickShorter: Bool
    ) -> WindowCandidate? {
        if let picked = pickCandidate(from: preferred, pickShorter: pickShorter) {
            return picked
        }
        return pickCandidate(from: fallback, pickShorter: pickShorter)
    }

    private nonisolated static func pickCandidate(
        from candidates: [WindowCandidate],
        pickShorter: Bool
    ) -> WindowCandidate? {
        guard !candidates.isEmpty else { return nil }
        return candidates.min(by: { lhs, rhs in
            if pickShorter {
                if lhs.resetInSec == rhs.resetInSec { return lhs.percent > rhs.percent }
                return lhs.resetInSec < rhs.resetInSec
            }
            if lhs.resetInSec == rhs.resetInSec { return lhs.percent > rhs.percent }
            return lhs.resetInSec > rhs.resetInSec
        })
    }

    private nonisolated static func buildSnapshot(
        rolling: [String: Any],
        weekly: [String: Any],
        monthly: [String: Any]?,
        now: Date,
        renewsAt: Date?
    ) -> ProviderUsageSnapshot? {
        guard let rollingWindow = parseWindow(rolling),
              let weeklyWindow = parseWindow(weekly)
        else {
            return nil
        }
        let monthlyWindow = monthly.flatMap { parseWindow($0) }
        return buildSnapshot(
            rollingPercent: rollingWindow.percent, rollingReset: rollingWindow.resetInSec,
            weeklyPercent: weeklyWindow.percent, weeklyReset: weeklyWindow.resetInSec,
            monthlyPercent: monthlyWindow?.percent, monthlyReset: monthlyWindow?.resetInSec,
            renewsAt: renewsAt, now: now)
    }

    private nonisolated static func buildSnapshot(
        rollingPercent: Double,
        rollingReset: Int,
        weeklyPercent: Double,
        weeklyReset: Int,
        monthlyPercent: Double?,
        monthlyReset: Int?,
        renewsAt: Date?,
        now: Date
    ) -> ProviderUsageSnapshot {
        var windows: [UsageWindow] = [
            UsageWindow(
                utilization: rollingPercent,
                resetsAt: now.addingTimeInterval(TimeInterval(max(0, rollingReset))),
                windowType: .openCodeGoFiveHour),
            UsageWindow(
                utilization: weeklyPercent,
                resetsAt: now.addingTimeInterval(TimeInterval(max(0, weeklyReset))),
                windowType: .openCodeGoWeekly)
        ]
        if let monthlyPercent, let monthlyReset {
            windows.append(UsageWindow(
                utilization: monthlyPercent,
                resetsAt: now.addingTimeInterval(TimeInterval(max(0, monthlyReset))),
                windowType: .openCodeGoMonthly))
        }
        // `renewsAt` is decoded but not currently surfaced — OpenCode credits
        // (zen balance) are deferred to 1.1, so there is no extraUsage to report.
        _ = renewsAt
        return ProviderUsageSnapshot(
            provider: .openCode,
            windows: windows,
            extraUsage: nil,
            planName: "Go",
            fetchedAt: now)
    }

    private nonisolated static func parseWindow(_ dict: [String: Any]) -> (percent: Double, resetInSec: Int)? {
        var percent = doubleValue(from: dict, keys: percentKeys)
        if percent == nil {
            let used = doubleValue(from: dict, keys: ["used", "usage", "consumed", "count", "usedTokens"])
            let limit = doubleValue(from: dict, keys: ["limit", "total", "quota", "max", "cap", "tokenLimit"])
            if let used, let limit, limit > 0 {
                percent = (used / limit) * 100
            }
        }
        guard var resolvedPercent = percent else { return nil }
        if resolvedPercent <= 1.0, resolvedPercent >= 0 {
            resolvedPercent *= 100
        }
        resolvedPercent = max(0, min(100, resolvedPercent))

        var resetInSec = intValue(from: dict, keys: resetInKeys)
        if resetInSec == nil {
            let resetAtValue = value(from: dict, keys: resetAtKeys)
            if let resetAt = dateValue(from: resetAtValue) {
                resetInSec = max(0, Int(resetAt.timeIntervalSince(Date())))
            }
        }
        return (resolvedPercent, max(0, resetInSec ?? 0))
    }

    // MARK: - Workspace ID extraction (ported from CodexBar)

    nonisolated static func parseWorkspaceIDs(text: String) -> [String] {
        let pattern = #"id\s*:\s*\"(wrk_[^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsrange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private nonisolated static func parseWorkspaceIDsFromJSON(text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return []
        }
        var results: [String] = []
        collectWorkspaceIDs(object: object, out: &results)
        return results
    }

    private nonisolated static func collectWorkspaceIDs(object: Any, out: inout [String]) {
        if let dict = object as? [String: Any] {
            for (_, value) in dict {
                collectWorkspaceIDs(object: value, out: &out)
            }
            return
        }
        if let array = object as? [Any] {
            for value in array {
                collectWorkspaceIDs(object: value, out: &out)
            }
            return
        }
        if let string = object as? String,
           string.hasPrefix("wrk_"), !out.contains(string)
        {
            out.append(string)
        }
    }

    // MARK: - Sign-out / error detection (ported from CodexBar)

    nonisolated static func looksSignedOut(text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("login")
            || lower.contains("sign in")
            || lower.contains("auth/authorize")
            || lower.contains("not associated with an account")
            || lower.contains("actor of type \"public\"")
    }

    private nonisolated static func isExplicitNullPayload(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("null") == .orderedSame { return true }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return false
        }
        return object is NSNull
    }

    private nonisolated static func extractServerErrorMessage(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            if let match = text.range(of: #"(?i)<title>([^<]+)</title>"#, options: .regularExpression) {
                return String(text[match].dropFirst(7).dropLast(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
        guard let dict = object as? [String: Any] else { return nil }
        if let message = dict["message"] as? String, !message.isEmpty { return message }
        if let error = dict["error"] as? String, !error.isEmpty { return error }
        if let detail = dict["detail"] as? String, !detail.isEmpty { return detail }
        return nil
    }

    // MARK: - Primitives

    nonisolated static func extractDouble(pattern: String, text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[range])
    }

    nonisolated static func extractInt(pattern: String, text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[range])
    }

    private nonisolated static func doubleValue(from dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = doubleValue(from: dict[key]) { return value }
        }
        return nil
    }

    private nonisolated static func intValue(from dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(from: dict[key]) { return value }
        }
        return nil
    }

    private nonisolated static func value(from dict: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dict[key] { return value }
        }
        return nil
    }

    private nonisolated static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let number as Double: number
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }

    private nonisolated static func intValue(from value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as NSNumber: number.intValue
        case let string as String: Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }

    private nonisolated static func dateValue(from value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = doubleValue(from: value) {
            if number > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }
        if let string = value as? String {
            if let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return dateValue(from: number)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string)
        }
        return nil
    }

    // MARK: - Config

    nonisolated struct DashboardConfig: Sendable, Equatable {
        /// Optional — auto-discovered from the cookie when nil.
        let workspaceID: String?
        let authCookie: String

        var dashboardURL: URL {
            guard let workspaceID else { return Self.baseURL }
            return URL(string: "https://opencode.ai/workspace/\(workspaceID)/go") ?? Self.baseURL
        }

        /// Normalizes the pasted cookie into a `Cookie` header value, supporting
        /// both `auth` and `__Host-auth` cookie names.
        var cookieHeader: String {
            if authCookie.contains("auth=") { return authCookie }
            return "auth=\(authCookie)"
        }

        private nonisolated static let baseURL = URL(string: "https://opencode.ai")!

        static func load(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
            defaults: UserDefaults = .standard
        ) -> DashboardConfig? {
            // UserDefaults (Settings UI) takes precedence — the primary path for 1.0+.
            if let cookie = defaults.string(forKey: Constants.OpenCode.cookieDefaultsKey),
               !cookie.isEmpty
            {
                return DashboardConfig(
                    workspaceID: normalizedWorkspaceID(defaults.string(forKey: Constants.OpenCode.workspaceIDDefaultsKey)),
                    authCookie: cookie)
            }

            // Env-var path: cookie required, workspace optional (auto-discovered).
            if let authCookie = environment["OPENCODE_GO_AUTH_COOKIE"],
               !authCookie.isEmpty
            {
                return DashboardConfig(
                    workspaceID: normalizedWorkspaceID(environment["OPENCODE_GO_WORKSPACE_ID"]),
                    authCookie: authCookie)
            }

            for url in configFileCandidates(environment: environment, homeDirectory: homeDirectory) {
                guard fileManager.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }
                let cookie = object["authCookie"] as? String
                    ?? object["auth_cookie"] as? String
                    ?? object["cookie"] as? String
                let workspace = object["workspaceId"] as? String
                    ?? object["workspaceID"] as? String
                    ?? object["workspace_id"] as? String
                if let cookie, !cookie.isEmpty {
                    return DashboardConfig(
                        workspaceID: normalizedWorkspaceID(workspace),
                        authCookie: cookie)
                }
            }
            return nil
        }

        private static func configFileCandidates(environment: [String: String], homeDirectory: URL) -> [URL] {
            var urls: [URL] = []
            if let override = environment["OPENCODE_GO_CONFIG_FILE"], !override.isEmpty {
                urls.append(URL(fileURLWithPath: override))
            }
            if let xdgConfig = environment["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
                let base = URL(fileURLWithPath: xdgConfig)
                urls.append(base.appendingPathComponent("opencode-bar/opencode-go.json"))
                urls.append(base.appendingPathComponent("opencode-quota/opencode-go.json"))
            }
            urls.append(homeDirectory.appendingPathComponent(".config/opencode-bar/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent(".config/opencode-quota/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent("Library/Application Support/opencode-bar/opencode-go.json"))
            urls.append(homeDirectory.appendingPathComponent("Library/Application Support/opencode-quota/opencode-go.json"))
            return urls
        }

        static func normalizedWorkspaceID(_ raw: String?) -> String? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if raw.hasPrefix("wrk_") { return raw }
            if URL(string: raw) != nil, let range = raw.range(of: #"/workspace/([^/]+)"#, options: .regularExpression) {
                let match = String(raw[range])
                return match.replacingOccurrences(of: "/workspace/", with: "")
            }
            if let match = raw.range(of: #"wrk_[A-Za-z0-9]+"#, options: .regularExpression) {
                return String(raw[match])
            }
            return nil
        }
    }
}

// MARK: - HTTP transport

protocol OpenCodeHTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default transport backed by an ephemeral `URLSession` that blocks
/// cross-host redirects (prevents cookie leakage to other domains).
struct OpenCodeURLSessionTransport: OpenCodeHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let delegate = RedirectGuardDelegate()
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Blocks HTTP redirects to a different host (cookie-leak protection).
private final class RedirectGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let allows = OpenCodeGoUsageService.allowsRedirect(
            from: task.originalRequest?.url, to: request.url)
        completionHandler(allows ? request : nil)
    }
}

extension OpenCodeGoUsageService {
    /// Whether a redirect from `source` to `destination` is safe (same host, HTTPS).
    nonisolated static func allowsRedirect(from sourceURL: URL?, to destinationURL: URL?) -> Bool {
        guard let sourceHost = sourceURL?.host?.lowercased(),
              let destinationHost = destinationURL?.host?.lowercased(),
              sourceHost == destinationHost,
              destinationURL?.scheme?.lowercased() == "https"
        else { return false }
        return true
    }
}
#endif
