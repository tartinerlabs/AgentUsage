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

/// Reads per-session token aggregates from OpenCode's SQLite DB
/// (`~/.local/share/opencode/opencode.db`, `session` table).
///
/// OpenCode stores a `cost` column but leaves it 0, so we recompute cost via
/// `ModelPricing` using each session's `model.providerID`. The DB is in WAL mode
/// with a live writer, so we open it read-only.
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
        let sql = """
        SELECT id, model, tokens_input, tokens_output, tokens_reasoning, \
        tokens_cache_read, tokens_cache_write, time_created \
        FROM session \
        WHERE time_created >= ? AND (tokens_input > 0 OR tokens_output > 0)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.tokenUsage.warning("OpenCode query prepare failed: \(String(cString: sqlite3_errmsg(db)))")
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

            let model = Self.parseModel(modelJSON)

            let tokens = TokenCount(
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                reasoningTokens: reasoning
            )

            entries.append(
                ProviderUsageEntry(
                    provider: model.provider,
                    model: model.id,
                    pricingProviderKey: model.providerID,
                    tokens: tokens,
                    timestamp: Date(timeIntervalSince1970: Double(timeCreatedMillis) / 1000),
                    dedupKey: "opencode:\(id)"
                    // cost column is always 0 → omit precomputedCostUSD, compute via ModelPricing
                )
            )
        }
        return entries
    }

    /// OpenCode stores `model` as JSON: `{"id":"gpt-5.5","providerID":"openai","variant":"…"}`.
    static func parseModel(_ json: String) -> (id: String, providerID: String, provider: Provider) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (json.isEmpty ? "unknown" : json, "unknown", .openCode)
        }
        let id = (obj["id"] as? String) ?? "unknown"
        let providerID = (obj["providerID"] as? String)
            ?? (obj["providerId"] as? String)
            ?? (obj["provider"] as? String)
            ?? "unknown"
        return (id, providerID, providerBucket(forProviderID: providerID))
    }

    static func providerBucket(forProviderID providerID: String) -> Provider {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai":
            return .codex
        case "opencode", "opencode-go", "opencode-zen":
            return .openCode
        default:
            return .openCode
        }
    }
}
#endif
