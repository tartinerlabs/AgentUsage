//
//  BlogUsageIndexStore.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import SQLite3

nonisolated enum BlogUsageIndexedSource: String, Sendable {
    case claude
    case codex
    case openCode = "opencode"
}

nonisolated struct BlogUsageFileCheckpoint: Sendable, Equatable {
    let source: BlogUsageIndexedSource
    let path: String
    let fileIdentifier: String?
    let fileSize: Int64
    let modificationTime: TimeInterval
    let byteOffset: Int64
    let currentModel: String
    let tailHash: String
    let sampleHash: String?
    let isComplete: Bool
}

nonisolated enum BlogUsageIndexStoreError: LocalizedError, Sendable {
    case open(String)
    case execute(String)
    case prepare(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let detail):
            return "Could not open the blog usage index: \(detail)"
        case .execute(let detail):
            return "Could not update the blog usage index: \(detail)"
        case .prepare(let detail):
            return "Could not prepare a blog usage index query: \(detail)"
        case .step(let detail):
            return "Could not read the blog usage index: \(detail)"
        }
    }
}

nonisolated protocol BlogUsageIndexStoring: AnyObject, Sendable {
    func withTransaction(_ body: () throws -> Void) throws
    func checkpoint(path: String) throws -> BlogUsageFileCheckpoint?
    func checkpoints() throws -> [BlogUsageFileCheckpoint]
    func saveCheckpoint(_ checkpoint: BlogUsageFileCheckpoint) throws
    func rebindFile(from oldPath: String, to newPath: String) throws
    func replaceRecord(
        source: BlogUsageIndexedSource,
        container: String,
        recordKey: String,
        dedupeKey: String?,
        event: BlogUsageEvent
    ) throws -> Bool
    func deleteRecord(source: BlogUsageIndexedSource, container: String, recordKey: String) throws -> Bool
    func deleteRecords(source: BlogUsageIndexedSource, container: String) throws -> Bool
    func aggregateRows() throws -> [BlogUsageIngestRow]
    func recordCount() throws -> Int
    func revision() throws -> Int64
    func advanceRevision() throws -> Int64
    func uploadedRevision(endpointKey: String) throws -> Int64
    func markUploaded(revision: Int64, endpointKey: String) throws
    func stringMetadata(forKey key: String) throws -> String?
    func setMetadata(_ value: String, forKey key: String) throws
}

/// Rebuildable, actor-confined SQLite cache used by `BlogUsageSourceIndexer`.
/// The class is `@unchecked Sendable` only so it can be injected into that actor;
/// all access remains serialized by the actor.
final class BlogUsageIndexStore: BlogUsageIndexStoring, @unchecked Sendable {
    private static let schemaVersion: Int32 = 1

    private let databaseURL: URL
    private let timeZoneIdentifier: String
    private let dayFormatter: DateFormatter
    private var database: OpaquePointer?

    init(databaseURL: URL, timeZoneIdentifier: String = TimeZone.current.identifier) throws {
        self.databaseURL = databaseURL
        self.timeZoneIdentifier = timeZoneIdentifier
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = .current
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = dayFormatter

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try openAndValidate()
        } catch {
            close()
            try removeDatabaseFiles()
            try openAndCreateSchema()
        }
    }

    deinit {
        close()
    }

    func withTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func checkpoint(path: String) throws -> BlogUsageFileCheckpoint? {
        let sql = """
        SELECT source, path, file_identifier, file_size, modification_time,
               byte_offset, current_model, tail_hash, sample_hash, is_complete
        FROM source_files WHERE path = ? LIMIT 1
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(path, to: 1, in: statement)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return checkpoint(from: statement)
        case SQLITE_DONE:
            return nil
        default:
            throw stepError()
        }
    }

    func checkpoints() throws -> [BlogUsageFileCheckpoint] {
        let statement = try prepare("""
        SELECT source, path, file_identifier, file_size, modification_time,
               byte_offset, current_model, tail_hash, sample_hash, is_complete
        FROM source_files
        """)
        defer { sqlite3_finalize(statement) }

        var result: [BlogUsageFileCheckpoint] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let value = checkpoint(from: statement) {
                    result.append(value)
                }
            case SQLITE_DONE:
                return result
            default:
                throw stepError()
            }
        }
    }

    func saveCheckpoint(_ checkpoint: BlogUsageFileCheckpoint) throws {
        let statement = try prepare("""
        INSERT INTO source_files (
            source, path, file_identifier, file_size, modification_time,
            byte_offset, current_model, tail_hash, sample_hash, is_complete
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            source = excluded.source,
            file_identifier = excluded.file_identifier,
            file_size = excluded.file_size,
            modification_time = excluded.modification_time,
            byte_offset = excluded.byte_offset,
            current_model = excluded.current_model,
            tail_hash = excluded.tail_hash,
            sample_hash = excluded.sample_hash,
            is_complete = excluded.is_complete
        """)
        defer { sqlite3_finalize(statement) }

        bind(checkpoint.source.rawValue, to: 1, in: statement)
        bind(checkpoint.path, to: 2, in: statement)
        bind(checkpoint.fileIdentifier, to: 3, in: statement)
        sqlite3_bind_int64(statement, 4, checkpoint.fileSize)
        sqlite3_bind_double(statement, 5, checkpoint.modificationTime)
        sqlite3_bind_int64(statement, 6, checkpoint.byteOffset)
        bind(checkpoint.currentModel, to: 7, in: statement)
        bind(checkpoint.tailHash, to: 8, in: statement)
        bind(checkpoint.sampleHash, to: 9, in: statement)
        sqlite3_bind_int(statement, 10, checkpoint.isComplete ? 1 : 0)
        try finish(statement)
    }

    func rebindFile(from oldPath: String, to newPath: String) throws {
        let updateRecords = try prepare("UPDATE usage_records SET container = ? WHERE container = ?")
        defer { sqlite3_finalize(updateRecords) }
        bind(newPath, to: 1, in: updateRecords)
        bind(oldPath, to: 2, in: updateRecords)
        try finish(updateRecords)

        let updateFile = try prepare("UPDATE source_files SET path = ? WHERE path = ?")
        defer { sqlite3_finalize(updateFile) }
        bind(newPath, to: 1, in: updateFile)
        bind(oldPath, to: 2, in: updateFile)
        try finish(updateFile)
    }

    @discardableResult
    func replaceRecord(
        source: BlogUsageIndexedSource,
        container: String,
        recordKey: String,
        dedupeKey: String?,
        event: BlogUsageEvent
    ) throws -> Bool {
        let statement = try prepare("""
        INSERT INTO usage_records (
            source, container, record_key, dedupe_key, timestamp, date,
            agent, provider, model, input_tokens, output_tokens,
            cache_read_tokens, cache_write_tokens, reasoning_tokens
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source, container, record_key) DO UPDATE SET
            dedupe_key = excluded.dedupe_key,
            timestamp = excluded.timestamp,
            date = excluded.date,
            agent = excluded.agent,
            provider = excluded.provider,
            model = excluded.model,
            input_tokens = excluded.input_tokens,
            output_tokens = excluded.output_tokens,
            cache_read_tokens = excluded.cache_read_tokens,
            cache_write_tokens = excluded.cache_write_tokens,
            reasoning_tokens = excluded.reasoning_tokens
        """)
        defer { sqlite3_finalize(statement) }

        bind(source.rawValue, to: 1, in: statement)
        bind(container, to: 2, in: statement)
        bind(recordKey, to: 3, in: statement)
        bind(dedupeKey, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, event.timestamp.timeIntervalSince1970)
        bind(dayFormatter.string(from: event.timestamp), to: 6, in: statement)
        bind(event.agent, to: 7, in: statement)
        bind(event.provider, to: 8, in: statement)
        bind(event.model, to: 9, in: statement)
        sqlite3_bind_int64(statement, 10, Int64(event.inputTokens))
        sqlite3_bind_int64(statement, 11, Int64(event.outputTokens))
        sqlite3_bind_int64(statement, 12, Int64(event.cacheReadTokens))
        sqlite3_bind_int64(statement, 13, Int64(event.cacheWriteTokens))
        sqlite3_bind_int64(statement, 14, Int64(event.reasoningTokens))
        try finish(statement)
        return sqlite3_changes(database) > 0
    }

    @discardableResult
    func deleteRecord(source: BlogUsageIndexedSource, container: String, recordKey: String) throws -> Bool {
        let statement = try prepare(
            "DELETE FROM usage_records WHERE source = ? AND container = ? AND record_key = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(source.rawValue, to: 1, in: statement)
        bind(container, to: 2, in: statement)
        bind(recordKey, to: 3, in: statement)
        try finish(statement)
        return sqlite3_changes(database) > 0
    }

    @discardableResult
    func deleteRecords(source: BlogUsageIndexedSource, container: String) throws -> Bool {
        let statement = try prepare("DELETE FROM usage_records WHERE source = ? AND container = ?")
        defer { sqlite3_finalize(statement) }
        bind(source.rawValue, to: 1, in: statement)
        bind(container, to: 2, in: statement)
        try finish(statement)
        return sqlite3_changes(database) > 0
    }

    func aggregateRows() throws -> [BlogUsageIngestRow] {
        // A record without a dedupe key is always canonical. For Claude and
        // OpenCode, keep the first occurrence in the same stable order used by
        // the previous full-history parser: source path, then record key.
        let statement = try prepare("""
        WITH canonical AS (
            SELECT record.*
            FROM usage_records AS record
            WHERE record.dedupe_key IS NULL
               OR NOT EXISTS (
                    SELECT 1
                    FROM usage_records AS earlier
                    WHERE earlier.source = record.source
                      AND earlier.dedupe_key = record.dedupe_key
                      AND (
                          earlier.container < record.container
                          OR (earlier.container = record.container AND earlier.record_key < record.record_key)
                      )
               )
        )
        SELECT date, agent, provider, model,
               SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
               SUM(cache_write_tokens), SUM(reasoning_tokens), COUNT(*)
        FROM canonical
        GROUP BY date, agent, provider, model
        ORDER BY date, agent, provider, model
        """)
        defer { sqlite3_finalize(statement) }

        var rows: [BlogUsageIngestRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let date = columnString(statement, index: 0) ?? ""
                let agent = columnString(statement, index: 1) ?? "unknown"
                let provider = columnString(statement, index: 2) ?? "unknown"
                let model = columnString(statement, index: 3) ?? "unknown"
                let input = Int(sqlite3_column_int64(statement, 4))
                let output = Int(sqlite3_column_int64(statement, 5))
                let cacheRead = Int(sqlite3_column_int64(statement, 6))
                let cacheWrite = Int(sqlite3_column_int64(statement, 7))
                let reasoning = Int(sqlite3_column_int64(statement, 8))
                let messages = Int(sqlite3_column_int64(statement, 9))
                let total = input + output + cacheRead + cacheWrite + reasoning
                let cost = ModelPricing.costUSD(
                    provider: provider,
                    model: model,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: cacheRead,
                    cacheWriteTokens: cacheWrite,
                    reasoningTokens: reasoning
                ).map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) }

                rows.append(BlogUsageIngestRow(
                    date: date,
                    agent: agent,
                    provider: provider,
                    model: model,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: cacheRead,
                    cacheWriteTokens: cacheWrite,
                    reasoningTokens: reasoning,
                    totalTokens: total,
                    costUsd: cost,
                    messages: messages
                ))
            case SQLITE_DONE:
                return rows
            default:
                throw stepError()
            }
        }
    }

    func recordCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM usage_records")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw stepError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func revision() throws -> Int64 {
        Int64(try stringMetadata(forKey: "revision") ?? "0") ?? 0
    }

    @discardableResult
    func advanceRevision() throws -> Int64 {
        let next = try revision() + 1
        try setMetadata(String(next), forKey: "revision")
        return next
    }

    func uploadedRevision(endpointKey: String) throws -> Int64 {
        Int64(try stringMetadata(forKey: "uploaded:\(endpointKey)") ?? "-1") ?? -1
    }

    func markUploaded(revision: Int64, endpointKey: String) throws {
        try setMetadata(String(revision), forKey: "uploaded:\(endpointKey)")
    }

    func stringMetadata(forKey key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return columnString(statement, index: 0)
        case SQLITE_DONE:
            return nil
        default:
            throw stepError()
        }
    }

    func setMetadata(_ value: String, forKey key: String) throws {
        let statement = try prepare("""
        INSERT INTO metadata (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """)
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        bind(value, to: 2, in: statement)
        try finish(statement)
    }

    private func openAndValidate() throws {
        try open()
        guard try quickCheckIsValid() else {
            throw BlogUsageIndexStoreError.open("integrity check failed")
        }

        let version = try userVersion()
        if version == 0 {
            try createSchema()
        } else if version != Self.schemaVersion {
            throw BlogUsageIndexStoreError.open("unsupported schema version \(version)")
        }

        if let storedTimeZone = try stringMetadata(forKey: "time-zone") {
            guard storedTimeZone == timeZoneIdentifier else {
                throw BlogUsageIndexStoreError.open("calendar time zone changed")
            }
        } else {
            try setMetadata(timeZoneIdentifier, forKey: "time-zone")
        }
    }

    private func openAndCreateSchema() throws {
        try open()
        try createSchema()
    }

    private func open() throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &pointer, flags, nil) == SQLITE_OK,
              let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let pointer { sqlite3_close(pointer) }
            throw BlogUsageIndexStoreError.open(message)
        }
        database = pointer
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    private func createSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS source_files (
            source TEXT NOT NULL,
            path TEXT PRIMARY KEY NOT NULL,
            file_identifier TEXT,
            file_size INTEGER NOT NULL,
            modification_time REAL NOT NULL,
            byte_offset INTEGER NOT NULL,
            current_model TEXT NOT NULL,
            tail_hash TEXT NOT NULL,
            sample_hash TEXT,
            is_complete INTEGER NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS usage_records (
            source TEXT NOT NULL,
            container TEXT NOT NULL,
            record_key TEXT NOT NULL,
            dedupe_key TEXT,
            timestamp REAL NOT NULL,
            date TEXT NOT NULL,
            agent TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            cache_read_tokens INTEGER NOT NULL,
            cache_write_tokens INTEGER NOT NULL,
            reasoning_tokens INTEGER NOT NULL,
            PRIMARY KEY (source, container, record_key)
        )
        """)
        try execute(
            "CREATE INDEX IF NOT EXISTS usage_records_dedupe ON usage_records(source, dedupe_key, container, record_key)"
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS usage_records_aggregate ON usage_records(date, agent, provider, model)"
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion)")
        try setMetadata(timeZoneIdentifier, forKey: "time-zone")
        try setMetadata("0", forKey: "revision")
    }

    private func quickCheckIsValid() throws -> Bool {
        let statement = try prepare("PRAGMA quick_check(1)")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return columnString(statement, index: 0) == "ok"
    }

    private func userVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw stepError() }
        return sqlite3_column_int(statement, 0)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw BlogUsageIndexStoreError.open("database is closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let detail = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw BlogUsageIndexStoreError.execute(detail)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw BlogUsageIndexStoreError.open("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw BlogUsageIndexStoreError.prepare(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw stepError() }
    }

    private func stepError() -> BlogUsageIndexStoreError {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
        return .step(detail)
    }

    private func checkpoint(from statement: OpaquePointer) -> BlogUsageFileCheckpoint? {
        guard let sourceValue = columnString(statement, index: 0),
              let source = BlogUsageIndexedSource(rawValue: sourceValue),
              let path = columnString(statement, index: 1) else {
            return nil
        }
        return BlogUsageFileCheckpoint(
            source: source,
            path: path,
            fileIdentifier: columnString(statement, index: 2),
            fileSize: sqlite3_column_int64(statement, 3),
            modificationTime: sqlite3_column_double(statement, 4),
            byteOffset: sqlite3_column_int64(statement, 5),
            currentModel: columnString(statement, index: 6) ?? "unknown",
            tailHash: columnString(statement, index: 7) ?? "",
            sampleHash: columnString(statement, index: 8),
            isComplete: sqlite3_column_int(statement, 9) != 0
        )
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func close() {
        guard let database else { return }
        sqlite3_close(database)
        self.database = nil
    }

    private func removeDatabaseFiles() throws {
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

}
#endif
