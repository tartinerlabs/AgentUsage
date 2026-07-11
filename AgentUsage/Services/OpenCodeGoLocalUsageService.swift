//
//  OpenCodeGoLocalUsageService.swift
//  AgentUsage
//
//  OpenCode Go quota windows reconstructed from local files — no cookie,
//  no workspace ID, no network. Mirrors what CodexBar's local reader does.
//

#if os(macOS)
import Foundation
import AgentUsageKit
import OSLog
import SQLite3

/// Rebuilds OpenCode Go's rolling / weekly / monthly usage windows entirely from
/// the on-device OpenCode data, so the app needs zero configuration:
///
/// - `~/.local/share/opencode/auth.json` — a non-empty `opencode-go.key` entry
///   confirms the user is signed in to OpenCode Go.
/// - `~/.local/share/opencode/opencode.db` — per-message `cost` for
///   `providerID = "opencode-go"` assistant messages (the same DB
///   `OpenCodeLogSource` already reads for token/cost).
///
/// Each window's percentage is the summed spend over that window against a fixed
/// plan spend limit. This is an approximation of the exact percentages the
/// authenticated dashboard reports, but requires no credentials.
actor OpenCodeGoLocalUsageService: ProviderUsageServiceProtocol {
    nonisolated let provider: Provider = .openCodeGo

    /// OpenCode Go plan spend limits, in USD, per window. These track the plan and
    /// may need updating if OpenCode changes the Go tier's limits.
    static let limits = (session: 12.0, weekly: 30.0, monthly: 60.0)

    private static let fiveHours: TimeInterval = 5 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60

    private let databaseURLs: [URL]
    private let authURLOverride: URL?
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - databaseURLs: Candidate `opencode.db` paths (defaults to the shared
    ///     `Constants.openCodeDatabaseURLs`, same as `OpenCodeLogSource`).
    ///   - authURL: Explicit `auth.json` path. When nil, resolved as a sibling of
    ///     whichever database path exists.
    init(
        databaseURLs: [URL] = Constants.openCodeDatabaseURLs,
        authURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.databaseURLs = databaseURLs
        self.authURLOverride = authURL
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        let fileManager = FileManager.default
        guard let dbURL = databaseURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }
        let authURL = authURLOverride
            ?? dbURL.deletingLastPathComponent().appendingPathComponent("auth.json")
        let hasAuth = Self.hasAuthKey(at: authURL)

        let rows = try Self.readRows(dbURL: dbURL)
        // Not signed in and no historical spend → OpenCode Go isn't in use; hide it.
        guard hasAuth || !rows.isEmpty else { return nil }
        // Signed in but nothing to show yet → also hide until there's usage.
        guard !rows.isEmpty else { return nil }

        return Self.makeSnapshot(rows: rows, now: now())
    }

    // MARK: - Auth detection

    /// True when `auth.json` carries a non-empty `opencode-go.key` (signed in).
    nonisolated static func hasAuthKey(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object["opencode-go"] as? [String: Any],
              let key = entry["key"] as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - SQLite

    struct UsageRow: Sendable, Equatable {
        let createdMs: Int64
        let cost: Double
    }

    /// Read `(createdMs, cost)` for OpenCode Go assistant messages. Opens the DB
    /// read-only (a live OpenCode process holds the WAL writer) and uses the
    /// `part` (`step-finish`) union when that table is present.
    nonisolated static func readRows(dbURL: URL) throws -> [UsageRow] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            Logger.tokenUsage.warning("OpenCode Go local DB open failed: \(message)")
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        let sql = hasTable(named: "part", db: db) ? messageAndPartUsageSQL : messageUsageSQL

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.tokenUsage.warning("OpenCode Go local query prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [UsageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let createdMs = sqlite3_column_int64(stmt, 0)
            let cost = sqlite3_column_double(stmt, 1)
            guard createdMs > 0, cost >= 0, cost.isFinite else { continue }
            rows.append(UsageRow(createdMs: createdMs, cost: cost))
        }
        return rows
    }

    private nonisolated static func hasTable(named name: String, db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private nonisolated static let messageUsageSQL = """
        SELECT
          CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
          CAST(json_extract(data, '$.cost') AS REAL) AS cost
        FROM message
        WHERE json_valid(data)
          AND json_extract(data, '$.providerID') = 'opencode-go'
          AND json_extract(data, '$.role') = 'assistant'
          AND json_type(data, '$.cost') IN ('integer', 'real')
    """

    private nonisolated static let messageAndPartUsageSQL = """
        WITH message_costs AS (
          SELECT
            id AS messageID,
            CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
            CAST(json_extract(data, '$.cost') AS REAL) AS cost
          FROM message
          WHERE json_valid(data)
            AND json_extract(data, '$.providerID') = 'opencode-go'
            AND json_extract(data, '$.role') = 'assistant'
            AND json_type(data, '$.cost') IN ('integer', 'real')
        )
        SELECT createdMs, cost
        FROM message_costs
        UNION ALL
        SELECT
          CAST(COALESCE(json_extract(p.data, '$.time.created'), p.time_created, m.time_created) AS INTEGER)
            AS createdMs,
          CAST(json_extract(p.data, '$.cost') AS REAL) AS cost
        FROM part p
        JOIN message m ON m.id = p.message_id
        WHERE json_valid(p.data)
          AND json_valid(m.data)
          AND json_extract(p.data, '$.type') = 'step-finish'
          AND json_type(p.data, '$.cost') IN ('integer', 'real')
          AND json_extract(m.data, '$.providerID') = 'opencode-go'
          AND json_extract(m.data, '$.role') = 'assistant'
          AND NOT EXISTS (
            SELECT 1
            FROM message_costs
            WHERE message_costs.messageID = p.message_id
          )
    """

    // MARK: - Snapshot

    /// Build the three OpenCode Go windows from `(createdMs, cost)` rows.
    nonisolated static func makeSnapshot(rows: [UsageRow], now: Date) -> ProviderUsageSnapshot {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let sessionStartMs = nowMs - Int64(fiveHours * 1000)
        let weekStartMs = Int64(startOfUTCWeek(now: now).timeIntervalSince1970 * 1000)
        let weekEndMs = weekStartMs + Int64(week * 1000)
        let earliestMs = rows.map(\.createdMs).min()
        let monthBounds = monthBounds(now: now, anchorMs: earliestMs)

        let sessionCost = sum(rows: rows, startMs: sessionStartMs, endMs: nowMs)
        let weeklyCost = sum(rows: rows, startMs: weekStartMs, endMs: weekEndMs)
        let monthlyCost = sum(rows: rows, startMs: monthBounds.startMs, endMs: monthBounds.endMs)

        let windows = [
            UsageWindow(
                utilization: percent(used: sessionCost, limit: limits.session),
                resetsAt: rollingReset(rows: rows, now: now),
                windowType: .openCodeGoFiveHour
            ),
            UsageWindow(
                utilization: percent(used: weeklyCost, limit: limits.weekly),
                resetsAt: Date(timeIntervalSince1970: Double(weekEndMs) / 1000),
                windowType: .openCodeGoWeekly
            ),
            UsageWindow(
                utilization: percent(used: monthlyCost, limit: limits.monthly),
                resetsAt: Date(timeIntervalSince1970: Double(monthBounds.endMs) / 1000),
                windowType: .openCodeGoMonthly
            )
        ]

        return ProviderUsageSnapshot(
            provider: .openCodeGo,
            windows: windows,
            planName: "Go",
            fetchedAt: now
        )
    }

    private nonisolated static func sum(rows: [UsageRow], startMs: Int64, endMs: Int64) -> Double {
        rows.reduce(0) { total, row in
            guard row.createdMs >= startMs, row.createdMs < endMs else { return total }
            return total + row.cost
        }
    }

    private nonisolated static func percent(used: Double, limit: Double) -> Double {
        guard used.isFinite, limit > 0 else { return 0 }
        let value = max(0, min(100, used / limit * 100))
        return (value * 10).rounded() / 10
    }

    /// Rolling window resets 5h after the oldest still-in-window message.
    private nonisolated static func rollingReset(rows: [UsageRow], now: Date) -> Date {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let sessionStartMs = nowMs - Int64(fiveHours * 1000)
        let oldestMs = rows
            .filter { $0.createdMs >= sessionStartMs && $0.createdMs < nowMs }
            .map(\.createdMs)
            .min() ?? nowMs
        let resetMs = oldestMs + Int64(fiveHours * 1000)
        return Date(timeIntervalSince1970: Double(max(resetMs, nowMs)) / 1000)
    }

    private nonisolated static func startOfUTCWeek(now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components) ?? now
    }

    private nonisolated static func monthBounds(now: Date, anchorMs: Int64?) -> (startMs: Int64, endMs: Int64) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

        guard let anchorMs else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
        }

        let anchor = Date(timeIntervalSince1970: TimeInterval(anchorMs) / 1000)
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)
        let nowComponents = calendar.dateComponents([.year, .month], from: now)

        var startMonthComponents = nowComponents
        var start = anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        if start > now {
            guard let previous = calendar.date(byAdding: .month, value: -1, to: start) else {
                let end = anchoredMonth(
                    calendar: calendar,
                    month: monthComponents(after: startMonthComponents, calendar: calendar),
                    anchor: anchorComponents
                )
                return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
            }
            startMonthComponents = calendar.dateComponents([.year, .month], from: previous)
            start = anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        }
        let end = anchoredMonth(
            calendar: calendar,
            month: monthComponents(after: startMonthComponents, calendar: calendar),
            anchor: anchorComponents
        )
        return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
    }

    private nonisolated static func monthComponents(after month: DateComponents, calendar: Calendar) -> DateComponents {
        let monthStart = calendar.date(from: month) ?? Date(timeIntervalSince1970: 0)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return calendar.dateComponents([.year, .month], from: nextMonth)
    }

    private nonisolated static func anchoredMonth(
        calendar: Calendar,
        month: DateComponents,
        anchor: DateComponents
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = month.year
        components.month = month.month
        components.day = anchor.day
        components.hour = anchor.hour
        components.minute = anchor.minute
        components.second = anchor.second
        components.nanosecond = anchor.nanosecond

        if let date = calendar.date(from: components),
           calendar.component(.month, from: date) == month.month {
            return date
        }

        components.day = calendar.range(of: .day, in: .month, for: calendar.date(from: month) ?? Date(timeIntervalSince1970: 0))?.count
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
#endif
