//
//  OpenCodeGoUsageService.swift
//  ClaudeMeter
//
//  OpenCode Go quota windows from the authenticated dashboard page.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog
import SQLite3

actor OpenCodeGoUsageService {
    nonisolated let provider: Provider = .openCode

    /// Spend limits per window for the Go tier (USD), used to synthesize quota
    /// percentages from local cost when the dashboard cookie isn't configured.
    private static let sessionLimitUSD = 12.0
    private static let weeklyLimitUSD = 30.0
    private static let monthlyLimitUSD = 60.0

    enum OpenCodeError: LocalizedError {
        /// The dashboard returned a 5xx status — treated as a service outage.
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .serverError(let code): return "OpenCode dashboard server error (\(code))"
            }
        }
    }

    private let session: URLSession
    private let configProvider: @Sendable () -> DashboardConfig?
    private let databaseURLs: [URL]
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        configProvider: @escaping @Sendable () -> DashboardConfig? = { DashboardConfig.load() },
        databaseURLs: [URL] = Constants.openCodeDatabaseURLs,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.configProvider = configProvider
        self.databaseURLs = databaseURLs
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        // No dashboard cookie configured → estimate windows from local spend so the
        // column isn't empty out of the box. Real percentages require the cookie.
        guard let config = configProvider() else {
            return localFallbackSnapshot(now: now())
        }
        var request = URLRequest(url: config.dashboardURL)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(config.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if (500...599).contains(http.statusCode) {
            // Server-side outage — surface it so the UI can show "service down".
            Logger.tokenUsage.warning("OpenCode Go dashboard returned \(http.statusCode)")
            throw OpenCodeError.serverError(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else {
            Logger.tokenUsage.warning("OpenCode Go dashboard request failed (\(http.statusCode))")
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseDashboardHTML(html, now: now())
    }

    nonisolated static func parseDashboardHTML(_ html: String, now: Date) -> ProviderUsageSnapshot? {
        let text = html.replacingOccurrences(of: #"\""#, with: #"""#)
        let specs: [(field: String, type: UsageWindowType)] = [
            ("rollingUsage", .openCodeGoFiveHour),
            ("weeklyUsage", .openCodeGoWeekly),
            ("monthlyUsage", .openCodeGoMonthly)
        ]

        let windows = specs.compactMap { spec -> UsageWindow? in
            guard let usage = extractNumber(field: spec.field, key: "usagePercent", text: text),
                  let resetSeconds = extractNumber(field: spec.field, key: "resetInSec", text: text) else {
                return nil
            }
            return UsageWindow(
                utilization: usage,
                resetsAt: now.addingTimeInterval(max(0, resetSeconds)),
                windowType: spec.type
            )
        }

        guard !windows.isEmpty else { return nil }
        return ProviderUsageSnapshot(
            provider: .openCode,
            windows: windows,
            planName: "Go",
            fetchedAt: now
        )
    }

    // MARK: - Local cost fallback (zero-config)

    /// Estimates Go quota windows from local OpenCode spend (`providerID == opencode-go`)
    /// against the per-window dollar limits. Used when no dashboard cookie is set.
    private func localFallbackSnapshot(now: Date) -> ProviderUsageSnapshot? {
        guard let dbURL = databaseURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }
        let rows = Self.readGoCostRows(dbURL: dbURL)
        guard !rows.isEmpty else { return nil }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utc.firstWeekday = 2 // Monday

        // Session: rolling 5-hour window; reset = oldest in-window event + 5h.
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let sessionRows = rows.filter { $0.date >= sessionStart }
        let sessionCost = sessionRows.reduce(0) { $0 + $1.cost }
        let sessionReset = sessionRows.map(\.date).min()?.addingTimeInterval(5 * 3600)
            ?? now.addingTimeInterval(5 * 3600)

        // Weekly: UTC week (Monday start).
        let weekStart = utc.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekReset = utc.date(byAdding: .day, value: 7, to: weekStart) ?? now.addingTimeInterval(7 * 86400)
        let weekCost = rows.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.cost }

        // Monthly: UTC calendar month.
        let monthStart = utc.dateInterval(of: .month, for: now)?.start ?? now
        let monthReset = utc.date(byAdding: .month, value: 1, to: monthStart) ?? now.addingTimeInterval(30 * 86400)
        let monthCost = rows.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.cost }

        func percent(_ cost: Double, _ limit: Double) -> Double {
            min(100, max(0, cost / limit * 100))
        }

        let windows = [
            UsageWindow(utilization: percent(sessionCost, Self.sessionLimitUSD), resetsAt: sessionReset, windowType: .openCodeGoFiveHour),
            UsageWindow(utilization: percent(weekCost, Self.weeklyLimitUSD), resetsAt: weekReset, windowType: .openCodeGoWeekly),
            UsageWindow(utilization: percent(monthCost, Self.monthlyLimitUSD), resetsAt: monthReset, windowType: .openCodeGoMonthly)
        ]
        return ProviderUsageSnapshot(provider: .openCode, windows: windows, planName: "Go", fetchedAt: now)
    }

    /// Reads `(timestamp, cost)` rows for `opencode-go` spend, trying the `message`
    /// table first and falling back to the `session` table.
    private nonisolated static func readGoCostRows(dbURL: URL) -> [(date: Date, cost: Double)] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        let messageSQL = """
        SELECT json_extract(data, '$.time.created'), json_extract(data, '$.cost') \
        FROM message \
        WHERE json_extract(data, '$.providerID') = 'opencode-go' \
        AND json_extract(data, '$.role') = 'assistant' \
        AND json_extract(data, '$.cost') > 0
        """
        if let rows = runCostQuery(db: db, sql: messageSQL), !rows.isEmpty {
            return rows
        }

        let sessionSQL = """
        SELECT time_created, cost FROM session \
        WHERE json_extract(model, '$.providerID') = 'opencode-go' AND cost > 0
        """
        return runCostQuery(db: db, sql: sessionSQL) ?? []
    }

    private nonisolated static func runCostQuery(db: OpaquePointer, sql: String) -> [(date: Date, cost: Double)]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var rows: [(date: Date, cost: Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let millis = sqlite3_column_int64(stmt, 0)
            let cost = sqlite3_column_double(stmt, 1)
            rows.append((date: Date(timeIntervalSince1970: Double(millis) / 1000), cost: cost))
        }
        return rows
    }

    private nonisolated static func extractNumber(field: String, key: String, text: String) -> Double? {
        let pattern = #"['\"]?"# + NSRegularExpression.escapedPattern(for: field) + #"['\"]?\s*:\s*(?:\$R\[\d+\]\s*=\s*)?\{[^}]*?['\"]?"# + NSRegularExpression.escapedPattern(for: key) + #"['\"]?\s*:\s*['\"]?(-?\d+(?:\.\d+)?)['\"]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    nonisolated struct DashboardConfig: Sendable, Equatable {
        let workspaceID: String
        let authCookie: String

        var dashboardURL: URL {
            URL(string: "https://opencode.ai/workspace/\(workspaceID)/go")!
        }

        var cookieHeader: String {
            authCookie.contains("auth=") ? authCookie : "auth=\(authCookie)"
        }

        static func load(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> DashboardConfig? {
            if let workspaceID = normalizedWorkspaceID(environment["OPENCODE_GO_WORKSPACE_ID"]),
               let authCookie = environment["OPENCODE_GO_AUTH_COOKIE"],
               !authCookie.isEmpty {
                return DashboardConfig(workspaceID: workspaceID, authCookie: authCookie)
            }

            for url in configFileCandidates(environment: environment, homeDirectory: homeDirectory) {
                guard fileManager.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let workspace = object["workspaceId"] as? String
                    ?? object["workspaceID"] as? String
                    ?? object["workspace_id"] as? String
                let cookie = object["authCookie"] as? String
                    ?? object["auth_cookie"] as? String
                    ?? object["cookie"] as? String
                if let workspaceID = normalizedWorkspaceID(workspace), let cookie, !cookie.isEmpty {
                    return DashboardConfig(workspaceID: workspaceID, authCookie: cookie)
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

        private static func normalizedWorkspaceID(_ raw: String?) -> String? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if raw.hasPrefix("wrk_") { return raw }
            if URL(string: raw) != nil, let range = raw.range(of: #"/workspace/([^/]+)"#, options: .regularExpression) {
                let match = String(raw[range])
                return match.replacingOccurrences(of: "/workspace/", with: "")
            }
            return nil
        }
    }
}
#endif
