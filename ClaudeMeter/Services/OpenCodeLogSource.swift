//
//  OpenCodeLogSource.swift
//  ClaudeMeter
//
//  Token/cost usage from OpenCode's local SQLite database.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog
import SQLite3

/// Reads token aggregates from OpenCode's SQLite DB
/// (`~/.local/share/opencode/opencode.db`).
///
/// Newer schemas store per-session aggregates in the `session` table; older/other
/// schemas only populate a per-message `message` table (JSON `data` column). We try
/// the `session` table first and fall back to `message` so usage isn't missed on
/// schema versions that don't aggregate into `session`.
///
/// OpenCode stores a `cost` column but typically leaves it 0, so we recompute cost
/// via `ModelPricing` using each row's `providerID`. The DB is in WAL mode with a
/// live writer, so we open it read-only.
actor OpenCodeLogSource: UsageLogSource {
    nonisolated let provider: Provider = .openCode

    private let fileManager = FileManager.default
    private let candidatePaths: [URL]

    init(candidatePaths: [URL] = Constants.openCodeDatabaseURLs) {
        self.candidatePaths = candidatePaths
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        guard let dbURL = candidatePaths.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return []
        }
        return try query(dbURL: dbURL, since: since)
    }

    // MARK: - SQLite

    private func query(dbURL: URL, since: Date) throws -> [ProviderUsageEntry] {
        var db: OpaquePointer?
        // Read-only; respect the active WAL of the running OpenCode process.
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            Logger.tokenUsage.warning("OpenCode DB open failed: \(msg)")
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        let sinceMillis = Int64(since.timeIntervalSince1970 * 1000)

        // Prefer the aggregated session table; fall back to per-message rows when it
        // yields nothing (table absent or not populated on this schema version).
        let sessionEntries = querySessionTable(db: db, sinceMillis: sinceMillis)
        if !sessionEntries.isEmpty {
            return sessionEntries
        }
        return queryMessageTable(db: db, sinceMillis: sinceMillis)
    }

    /// Per-session aggregates from the `session` table.
    private func querySessionTable(db: OpaquePointer, sinceMillis: Int64) -> [ProviderUsageEntry] {
        let sql = """
        SELECT id, model, tokens_input, tokens_output, tokens_reasoning, \
        tokens_cache_read, tokens_cache_write, time_created \
        FROM session \
        WHERE time_created >= ? AND (tokens_input > 0 OR tokens_output > 0)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            // Table/columns absent on this schema — caller falls back to `message`.
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sinceMillis)

        var entries: [ProviderUsageEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let modelJSON = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let input = Int(sqlite3_column_int64(stmt, 2))
            let output = Int(sqlite3_column_int64(stmt, 3))
            let reasoning = Int(sqlite3_column_int64(stmt, 4))
            let cacheRead = Int(sqlite3_column_int64(stmt, 5))
            let cacheWrite = Int(sqlite3_column_int64(stmt, 6))
            let timeCreatedMillis = sqlite3_column_int64(stmt, 7)

            let (modelId, providerKey) = Self.parseModel(modelJSON)

            let tokens = TokenCount(
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                reasoningTokens: reasoning
            )

            entries.append(
                ProviderUsageEntry(
                    provider: .openCode,
                    model: modelId,
                    pricingProviderKey: providerKey,
                    tokens: tokens,
                    timestamp: Date(timeIntervalSince1970: Double(timeCreatedMillis) / 1000),
                    dedupKey: "opencode:\(id)"
                    // cost column is always 0 → omit precomputedCostUSD, compute via ModelPricing
                )
            )
        }
        return entries
    }

    /// Per-message rows from the `message` table (JSON `data` column). Used when the
    /// `session` aggregate is unavailable. Honors a recorded `cost` when present.
    private func queryMessageTable(db: OpaquePointer, sinceMillis: Int64) -> [ProviderUsageEntry] {
        let sql = """
        SELECT id, \
        json_extract(data, '$.modelID'), \
        json_extract(data, '$.providerID'), \
        json_extract(data, '$.tokens.input'), \
        json_extract(data, '$.tokens.output'), \
        json_extract(data, '$.tokens.reasoning'), \
        json_extract(data, '$.tokens.cache.read'), \
        json_extract(data, '$.tokens.cache.write'), \
        json_extract(data, '$.time.created'), \
        json_extract(data, '$.cost') \
        FROM message \
        WHERE json_extract(data, '$.role') = 'assistant' \
        AND json_extract(data, '$.time.created') >= ? \
        AND (json_extract(data, '$.tokens.input') > 0 OR json_extract(data, '$.tokens.output') > 0)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.tokenUsage.warning("OpenCode message-table query unavailable: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sinceMillis)

        var entries: [ProviderUsageEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let modelId = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "unknown"
            let providerKey = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "openai"
            let input = Int(sqlite3_column_int64(stmt, 3))
            let output = Int(sqlite3_column_int64(stmt, 4))
            let reasoning = Int(sqlite3_column_int64(stmt, 5))
            let cacheRead = Int(sqlite3_column_int64(stmt, 6))
            let cacheWrite = Int(sqlite3_column_int64(stmt, 7))
            let timeCreatedMillis = sqlite3_column_int64(stmt, 8)
            let recordedCost = sqlite3_column_double(stmt, 9)

            let tokens = TokenCount(
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                reasoningTokens: reasoning
            )

            entries.append(
                ProviderUsageEntry(
                    provider: .openCode,
                    model: modelId,
                    pricingProviderKey: providerKey,
                    tokens: tokens,
                    timestamp: Date(timeIntervalSince1970: Double(timeCreatedMillis) / 1000),
                    dedupKey: "opencode:msg:\(id)",
                    precomputedCostUSD: recordedCost > 0 ? recordedCost : nil
                )
            )
        }
        return entries
    }

    /// OpenCode stores `model` as JSON: `{"id":"gpt-5.5","providerID":"openai","variant":"…"}`.
    static func parseModel(_ json: String) -> (model: String, pricingProviderKey: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (json.isEmpty ? "unknown" : json, "openai")
        }
        let id = (obj["id"] as? String) ?? "unknown"
        let providerID = (obj["providerID"] as? String) ?? "openai"
        return (id, providerID)
    }
}
#endif
