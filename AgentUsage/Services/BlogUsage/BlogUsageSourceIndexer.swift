//
//  BlogUsageSourceIndexer.swift
//  AgentUsage
//

#if os(macOS)
import CryptoKit
import Foundation
import OSLog
import SQLite3

nonisolated struct BlogUsageIndexResult: Sendable, Equatable {
    let bytesRead: Int
    let filesProcessed: Int
    let filesSkipped: Int
    let recordsProcessed: Int
    let changedRecords: Int
    let cacheRows: Int
    let maximumBufferedBytes: Int
    let remainingSources: Int

    var isBackfillInProgress: Bool {
        remainingSources > 0
    }
}

nonisolated protocol BlogUsageIndexing: Sendable {
    func index(maximumBytes: Int) async throws -> BlogUsageIndexResult
    func rows() async throws -> [BlogUsageIngestRow]
    func revision() async throws -> Int64
    func uploadedRevision(endpoint: String) async throws -> Int64
    func markUploaded(revision: Int64, endpoint: String) async throws
}

actor BlogUsageSourceIndexer: BlogUsageIndexing {
    nonisolated static let passiveByteBudget = 32 * 1_024 * 1_024
    nonisolated static let manualByteBudget = 128 * 1_024 * 1_024
    nonisolated static let readChunkSize = 256 * 1_024

    private nonisolated static let yieldByteInterval = 4 * 1_024 * 1_024
    private nonisolated static let fingerprintByteCount = 4 * 1_024
    private nonisolated static let logger = Logger(
        subsystem: "com.tartinerlabs.AgentUsage",
        category: "BlogUsageSync"
    )

    private let parser: BlogUsageSourceParser
    private let storeFactory: @Sendable () throws -> any BlogUsageIndexStoring
    private var cachedStore: (any BlogUsageIndexStoring)?

    init(
        parser: BlogUsageSourceParser = BlogUsageSourceParser(),
        databaseURL: URL = BlogUsageSourceIndexer.defaultDatabaseURL()
    ) {
        self.parser = parser
        self.storeFactory = { try BlogUsageIndexStore(databaseURL: databaseURL) }
    }

    init(
        parser: BlogUsageSourceParser = BlogUsageSourceParser(),
        store: any BlogUsageIndexStoring
    ) {
        self.parser = parser
        self.storeFactory = { store }
    }

    func index(maximumBytes: Int) async throws -> BlogUsageIndexResult {
        let startedAt = Date()
        let store = try store()
        let budget = max(1, maximumBytes)
        let openCodeBudget = min(Self.yieldByteInterval, max(1, budget / 4))
        let openCodeResult = try processOpenCode(maximumBytes: openCodeBudget, store: store)
        var metrics = MutableMetrics(openCodeResult)
        await Task.yield()

        let remainingBudget = max(1, budget - metrics.bytesRead)
        let files = try discoverJSONLFiles()
        let currentPaths = Set(files.map(\.url.path))
        var checkpoints = Dictionary(
            uniqueKeysWithValues: try store.checkpoints().map { ($0.path, $0) }
        )
        try reconcileMovedFiles(
            files,
            currentPaths: currentPaths,
            checkpoints: &checkpoints,
            store: store
        )
        let work = pendingFiles(from: files, checkpoints: checkpoints)
        metrics.filesSkipped += files.count - work.count

        for file in work where metrics.bytesRead < budget {
            var isComplete = false
            var countedFile = false
            while !isComplete, metrics.bytesRead < budget {
                let sliceBudget = min(
                    Self.yieldByteInterval,
                    max(1, remainingBudget - max(0, metrics.bytesRead - openCodeResult.bytesRead))
                )
                let result = try processJSONLFile(file, maximumBytes: sliceBudget, store: store)
                metrics.merge(result, countFile: !countedFile)
                countedFile = countedFile || result.filesProcessed > 0
                isComplete = result.isComplete
                await Task.yield()
            }
        }

        let updatedCheckpoints = Dictionary(
            uniqueKeysWithValues: try store.checkpoints().map { ($0.path, $0) }
        )
        metrics.remainingSources = remainingSourceCount(files: files, checkpoints: updatedCheckpoints)
            + (try openCodeBackfillIsComplete(store: store) ? 0 : 1)
        metrics.cacheRows = try store.recordCount()

        let elapsed = Date().timeIntervalSince(startedAt)
        Self.logger.info(
            "Blog usage index: bytes=\(metrics.bytesRead), files=\(metrics.filesProcessed), skipped=\(metrics.filesSkipped), records=\(metrics.recordsProcessed), changed=\(metrics.changedRecords), rows=\(metrics.cacheRows), buffer=\(metrics.maximumBufferedBytes), remaining=\(metrics.remainingSources), seconds=\(elapsed, format: .fixed(precision: 3))"
        )
        return metrics.result
    }

    func rows() throws -> [BlogUsageIngestRow] {
        try store().aggregateRows()
    }

    func revision() throws -> Int64 {
        try store().revision()
    }

    func uploadedRevision(endpoint: String) throws -> Int64 {
        try store().uploadedRevision(endpointKey: Self.endpointKey(endpoint))
    }

    func markUploaded(revision: Int64, endpoint: String) throws {
        try store().markUploaded(revision: revision, endpointKey: Self.endpointKey(endpoint))
    }

    nonisolated static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("BlogUsageSync", isDirectory: true)
            .appendingPathComponent("usage-index.sqlite")
    }

    private func store() throws -> any BlogUsageIndexStoring {
        if let cachedStore { return cachedStore }
        let value = try storeFactory()
        cachedStore = value
        return value
    }

    // MARK: - JSONL discovery and incremental parsing

    private func discoverJSONLFiles() throws -> [DiscoveredFile] {
        let roots: [(BlogUsageIndexedSource, URL)] = [
            (.claude, parser.homeDirectory.appendingPathComponent(".claude/projects")),
            (.claude, parser.homeDirectory.appendingPathComponent(".config/claude/projects")),
            (.codex, parser.homeDirectory.appendingPathComponent(".codex/sessions")),
            (.codex, parser.homeDirectory.appendingPathComponent(".codex/archived_sessions"))
        ]
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]
        var result: [DiscoveredFile] = []

        for (source, root) in roots {
            guard parser.fileManager.fileExists(atPath: root.path),
                  let enumerator = parser.fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true else {
                    continue
                }
                result.append(DiscoveredFile(
                    source: source,
                    url: url,
                    fileIdentifier: Self.fileIdentifier(values.fileResourceIdentifier),
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    private func reconcileMovedFiles(
        _ files: [DiscoveredFile],
        currentPaths: Set<String>,
        checkpoints: inout [String: BlogUsageFileCheckpoint],
        store: any BlogUsageIndexStoring
    ) throws {
        for file in files where checkpoints[file.url.path] == nil {
            let missing = checkpoints.values
                .filter { !currentPaths.contains($0.path) && $0.source == file.source }
                .sorted { $0.path < $1.path }
            var match = missing.first {
                file.fileIdentifier != nil && $0.fileIdentifier == file.fileIdentifier
            }

            if match == nil, !missing.isEmpty {
                let sample = try sampledHash(of: file.url, size: file.fileSize)
                match = missing.first { $0.fileSize == file.fileSize && $0.sampleHash == sample }
            }

            if let match {
                try store.withTransaction {
                    try store.rebindFile(from: match.path, to: file.url.path)
                    let rebound = BlogUsageFileCheckpoint(
                        source: match.source,
                        path: file.url.path,
                        fileIdentifier: file.fileIdentifier,
                        fileSize: file.fileSize,
                        modificationTime: file.modificationDate.timeIntervalSince1970,
                        byteOffset: match.byteOffset,
                        currentModel: match.currentModel,
                        tailHash: match.tailHash,
                        sampleHash: match.sampleHash,
                        isComplete: match.isComplete
                    )
                    try store.saveCheckpoint(rebound)
                    checkpoints.removeValue(forKey: match.path)
                    checkpoints[file.url.path] = rebound
                }
            }
        }
    }

    private func pendingFiles(
        from files: [DiscoveredFile],
        checkpoints: [String: BlogUsageFileCheckpoint]
    ) -> [DiscoveredFile] {
        let pairs = files.map { file in
            (file, checkpoints[file.url.path])
        }
        return pairs
            .filter { file, checkpoint in
                guard let checkpoint else { return true }
                return !checkpoint.isComplete
                    || checkpoint.fileSize != file.fileSize
                    || checkpoint.modificationTime != file.modificationDate.timeIntervalSince1970
            }
            .sorted { left, right in
                let leftIndexed = left.1 != nil
                let rightIndexed = right.1 != nil
                if leftIndexed != rightIndexed { return leftIndexed }
                if left.0.modificationDate != right.0.modificationDate {
                    return left.0.modificationDate > right.0.modificationDate
                }
                return left.0.url.path < right.0.url.path
            }
            .map(\.0)
    }

    private func processJSONLFile(
        _ file: DiscoveredFile,
        maximumBytes: Int,
        store: any BlogUsageIndexStoring
    ) throws -> FileProcessResult {
        let checkpoint = try validatedCheckpoint(for: file, store: store)
        let startOffset = checkpoint?.byteOffset ?? 0
        var currentModel = checkpoint?.currentModel ?? "unknown"
        guard let handle = try? FileHandle(forReadingFrom: file.url) else {
            return .unreadable
        }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, startOffset)))

        var pending = Data()
        var pendingOffset = startOffset
        var bytesRead = 0
        var recordsProcessed = 0
        var changedRecords = 0
        var maximumBufferedBytes = 0
        var reachedEnd = false

        try store.withTransaction {
            while bytesRead < maximumBytes || !pending.isEmpty {
                let remaining = maximumBytes - bytesRead
                if remaining <= 0, pending.isEmpty { break }
                let isOversizedContinuation = remaining <= 0
                let requested = remaining > 0
                    ? min(Self.readChunkSize, remaining)
                    : Self.readChunkSize
                guard let chunk = try handle.read(upToCount: max(1, requested)), !chunk.isEmpty else {
                    reachedEnd = true
                    break
                }
                bytesRead += chunk.count
                pending.append(chunk)
                maximumBufferedBytes = max(maximumBufferedBytes, pending.count)

                var scanStart = pending.startIndex
                var consumedThrough = pending.startIndex
                var stoppedAfterOversizedRecord = false
                while let newline = pending[scanStart...].firstIndex(of: 0x0A) {
                    let relativeOffset = pending.distance(from: pending.startIndex, to: scanStart)
                    var line = Data(pending[scanStart..<newline])
                    if line.last == 0x0D { line.removeLast() }
                    if try processJSONLRecord(
                        line,
                        source: file.source,
                        container: file.url.path,
                        byteOffset: pendingOffset + Int64(relativeOffset),
                        currentModel: &currentModel,
                        store: store
                    ) {
                        changedRecords += 1
                    }
                    recordsProcessed += 1
                    consumedThrough = pending.index(after: newline)
                    scanStart = consumedThrough

                    if isOversizedContinuation {
                        stoppedAfterOversizedRecord = true
                        break
                    }
                }

                let consumed = pending.distance(from: pending.startIndex, to: consumedThrough)
                if consumed > 0 {
                    pending.removeSubrange(pending.startIndex..<consumedThrough)
                    pendingOffset += Int64(consumed)
                }
                if stoppedAfterOversizedRecord {
                    if !pending.isEmpty {
                        try handle.seek(toOffset: UInt64(pendingOffset))
                        bytesRead -= pending.count
                        pending.removeAll(keepingCapacity: false)
                    }
                    break
                }
                if bytesRead >= maximumBytes, pending.isEmpty { break }
            }

            if pendingOffset >= file.fileSize {
                reachedEnd = true
            }
            let updatedCheckpoint = BlogUsageFileCheckpoint(
                source: file.source,
                path: file.url.path,
                fileIdentifier: file.fileIdentifier,
                fileSize: file.fileSize,
                modificationTime: file.modificationDate.timeIntervalSince1970,
                byteOffset: pendingOffset,
                currentModel: currentModel,
                tailHash: try tailHash(of: file.url, endingAt: pendingOffset),
                sampleHash: reachedEnd ? try sampledHash(of: file.url, size: file.fileSize) : checkpoint?.sampleHash,
                isComplete: reachedEnd
            )
            try store.saveCheckpoint(updatedCheckpoint)
            if changedRecords > 0 {
                try store.advanceRevision()
            }
        }

        return FileProcessResult(
            bytesRead: bytesRead,
            filesProcessed: 1,
            recordsProcessed: recordsProcessed,
            changedRecords: changedRecords,
            maximumBufferedBytes: maximumBufferedBytes,
            isComplete: reachedEnd
        )
    }

    private func validatedCheckpoint(
        for file: DiscoveredFile,
        store: any BlogUsageIndexStoring
    ) throws -> BlogUsageFileCheckpoint? {
        guard let checkpoint = try store.checkpoint(path: file.url.path) else { return nil }
        let sizeShrank = file.fileSize < checkpoint.byteOffset
        let identityChanged = checkpoint.fileIdentifier != nil
            && file.fileIdentifier != nil
            && checkpoint.fileIdentifier != file.fileIdentifier
        var prefixChanged = false

        if !sizeShrank, checkpoint.byteOffset > 0,
           checkpoint.fileSize != file.fileSize
            || checkpoint.modificationTime != file.modificationDate.timeIntervalSince1970 {
            prefixChanged = try tailHash(of: file.url, endingAt: checkpoint.byteOffset) != checkpoint.tailHash
            if !prefixChanged,
               file.fileSize == checkpoint.fileSize,
               let sampleHash = checkpoint.sampleHash {
                prefixChanged = try sampledHash(of: file.url, size: file.fileSize) != sampleHash
            }
        }

        guard sizeShrank || identityChanged || prefixChanged else { return checkpoint }
        try store.withTransaction {
            let removedRecords = try store.deleteRecords(source: file.source, container: file.url.path)
            try store.saveCheckpoint(BlogUsageFileCheckpoint(
                source: file.source,
                path: file.url.path,
                fileIdentifier: file.fileIdentifier,
                fileSize: file.fileSize,
                modificationTime: file.modificationDate.timeIntervalSince1970,
                byteOffset: 0,
                currentModel: "unknown",
                tailHash: "",
                sampleHash: nil,
                isComplete: false
            ))
            if removedRecords { try store.advanceRevision() }
        }
        return try store.checkpoint(path: file.url.path)
    }

    private func processJSONLRecord(
        _ data: Data,
        source: BlogUsageIndexedSource,
        container: String,
        byteOffset: Int64,
        currentModel: inout String,
        store: any BlogUsageIndexStoring
    ) throws -> Bool {
        let recordKey = String(format: "%020lld", byteOffset)
        switch source {
        case .claude:
            guard let parsed = autoreleasepool(invoking: { parser.parseClaudeLine(data) }) else {
                return false
            }
            return try store.replaceRecord(
                source: source,
                container: container,
                recordKey: recordKey,
                dedupeKey: parsed.dedupeID,
                event: parsed.event
            )
        case .codex:
            guard let event = autoreleasepool(invoking: {
                parser.parseCodexLine(data, currentModel: &currentModel)
            }) else {
                return false
            }
            return try store.replaceRecord(
                source: source,
                container: container,
                recordKey: recordKey,
                dedupeKey: nil,
                event: event
            )
        case .openCode:
            return false
        }
    }

    private func remainingSourceCount(
        files: [DiscoveredFile],
        checkpoints: [String: BlogUsageFileCheckpoint]
    ) -> Int {
        files.reduce(into: 0) { count, file in
            guard let checkpoint = checkpoints[file.url.path],
                  checkpoint.isComplete,
                  checkpoint.fileSize == file.fileSize,
                  checkpoint.modificationTime == file.modificationDate.timeIntervalSince1970 else {
                count += 1
                return
            }
        }
    }

    // MARK: - OpenCode incremental indexing

    private func processOpenCode(maximumBytes: Int, store: any BlogUsageIndexStoring) throws -> OpenCodeProcessResult {
        let url = parser.openCodeDatabaseURL()
        guard parser.fileManager.fileExists(atPath: url.path) else { return .empty }
        var sourceDatabase: OpaquePointer?
        guard sqlite3_open_v2(url.path, &sourceDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let sourceDatabase else {
            if let sourceDatabase { sqlite3_close(sourceDatabase) }
            return .empty
        }
        defer { sqlite3_close(sourceDatabase) }

        guard let schema = openCodeSchema(database: sourceDatabase) else { return .empty }
        let namespace = try openCodeNamespace(url: url)
        let initializedKey = "opencode:\(namespace):initialized"
        let liveKey = "opencode:\(namespace):live"
        let backfillKey = "opencode:\(namespace):backfill"
        let backfillCompleteKey = "opencode:\(namespace):backfill-complete"

        if try store.stringMetadata(forKey: initializedKey) != "1" {
            let maximum = try maximumOpenCodeCursor(database: sourceDatabase, schema: schema)
            try store.withTransaction {
                try store.setMetadata(Self.encodeCursor(maximum ?? OpenCodeCursor(value: "0", id: "")), forKey: liveKey)
                try store.setMetadata(maximum == nil ? "1" : "0", forKey: backfillCompleteKey)
                try store.setMetadata("1", forKey: initializedKey)
            }
        }

        var result = OpenCodeProcessResult.empty
        if let liveCursor = Self.decodeCursor(try store.stringMetadata(forKey: liveKey)) {
            let live = try processOpenCodeQuery(
                database: sourceDatabase,
                schema: schema,
                direction: .forward(after: liveCursor),
                maximumBytes: maximumBytes,
                container: url.path,
                store: store
            )
            result.merge(live)
            if let cursor = live.lastCursor {
                try store.setMetadata(Self.encodeCursor(cursor), forKey: liveKey)
            }
        }

        let remaining = maximumBytes - result.bytesRead
        if remaining > 0, try store.stringMetadata(forKey: backfillCompleteKey) != "1" {
            let cursor = Self.decodeCursor(try store.stringMetadata(forKey: backfillKey))
            let backfill = try processOpenCodeQuery(
                database: sourceDatabase,
                schema: schema,
                direction: .backward(before: cursor),
                maximumBytes: remaining,
                container: url.path,
                store: store
            )
            result.merge(backfill)
            if let last = backfill.lastCursor {
                try store.setMetadata(Self.encodeCursor(last), forKey: backfillKey)
            }
            if backfill.exhausted {
                try store.setMetadata("1", forKey: backfillCompleteKey)
            }
        }

        return result
    }

    private func processOpenCodeQuery(
        database: OpaquePointer,
        schema: OpenCodeSchema,
        direction: OpenCodeDirection,
        maximumBytes: Int,
        container: String,
        store: any BlogUsageIndexStoring
    ) throws -> OpenCodeProcessResult {
        let query = openCodeQuery(schema: schema, direction: direction)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query.sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in query.bindings.enumerated() {
            Self.bind(value, to: Int32(index + 1), in: statement)
        }

        var result = OpenCodeProcessResult.empty
        try store.withTransaction {
            while result.bytesRead < maximumBytes {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE {
                    result.exhausted = true
                    break
                }
                guard step == SQLITE_ROW,
                      let dataText = Self.columnString(statement, index: 0),
                      let data = dataText.data(using: .utf8),
                      let cursorValue = Self.columnString(statement, index: 1),
                      let recordID = Self.columnString(statement, index: 2) else {
                    if step != SQLITE_ROW { break }
                    continue
                }

                result.bytesRead += data.count
                result.maximumBufferedBytes = max(result.maximumBufferedBytes, data.count)
                result.recordsProcessed += 1
                result.lastCursor = OpenCodeCursor(value: cursorValue, id: recordID)
                let event = autoreleasepool(invoking: {
                    parser.parseOpenCodeMessageData(data, fallbackID: recordID, timestamp: parser.now())
                })
                let changed: Bool
                if let event {
                    changed = try store.replaceRecord(
                        source: .openCode,
                        container: container,
                        recordKey: recordID,
                        dedupeKey: recordID,
                        event: event
                    )
                } else {
                    changed = try store.deleteRecord(source: .openCode, container: container, recordKey: recordID)
                }
                if changed { result.changedRecords += 1 }
            }
            if result.changedRecords > 0 { try store.advanceRevision() }
        }
        return result
    }

    private func openCodeSchema(database: OpaquePointer) -> OpenCodeSchema? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(message)", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = Self.columnString(statement, index: 1) { columns.insert(name) }
        }
        guard columns.contains("data") else { return nil }
        let id = ["id", "messageID", "message_id"].first { columns.contains($0) }
        let updated = [
            "time_updated", "timeUpdated", "updatedAt", "updated_at",
            "createdAt", "created_at", "time_created", "timestamp", "time", "created"
        ].first { columns.contains($0) }
        guard let updated else { return nil }
        return OpenCodeSchema(idExpression: id.map(Self.quoteIdentifier) ?? "rowid", updatedColumn: Self.quoteIdentifier(updated))
    }

    private func maximumOpenCodeCursor(
        database: OpaquePointer,
        schema: OpenCodeSchema
    ) throws -> OpenCodeCursor? {
        let sql = """
        SELECT CAST(\(schema.updatedColumn) AS TEXT), CAST(\(schema.idExpression) AS TEXT)
        FROM message
        ORDER BY \(schema.updatedColumn) DESC, \(schema.idExpression) DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = Self.columnString(statement, index: 0),
              let id = Self.columnString(statement, index: 1) else {
            return nil
        }
        return OpenCodeCursor(value: value, id: id)
    }

    private func openCodeQuery(
        schema: OpenCodeSchema,
        direction: OpenCodeDirection
    ) -> (sql: String, bindings: [String]) {
        let selected = "data, CAST(\(schema.updatedColumn) AS TEXT), CAST(\(schema.idExpression) AS TEXT)"
        switch direction {
        case .forward(let cursor):
            return (
                """
                SELECT \(selected) FROM message
                WHERE \(schema.updatedColumn) > ?
                   OR (\(schema.updatedColumn) = ? AND \(schema.idExpression) > ?)
                ORDER BY \(schema.updatedColumn) ASC, \(schema.idExpression) ASC
                """,
                [cursor.value, cursor.value, cursor.id]
            )
        case .backward(let cursor):
            guard let cursor else {
                return (
                    "SELECT \(selected) FROM message ORDER BY \(schema.updatedColumn) DESC, \(schema.idExpression) DESC",
                    []
                )
            }
            return (
                """
                SELECT \(selected) FROM message
                WHERE \(schema.updatedColumn) < ?
                   OR (\(schema.updatedColumn) = ? AND \(schema.idExpression) < ?)
                ORDER BY \(schema.updatedColumn) DESC, \(schema.idExpression) DESC
                """,
                [cursor.value, cursor.value, cursor.id]
            )
        }
    }

    private func openCodeBackfillIsComplete(store: any BlogUsageIndexStoring) throws -> Bool {
        let url = parser.openCodeDatabaseURL()
        guard parser.fileManager.fileExists(atPath: url.path) else { return true }
        let namespace = try openCodeNamespace(url: url)
        return try store.stringMetadata(forKey: "opencode:\(namespace):backfill-complete") == "1"
    }

    private func openCodeNamespace(url: URL) throws -> String {
        let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        let identity = Self.fileIdentifier(values?.fileResourceIdentifier) ?? "path"
        return Self.sha256("\(url.path)|\(identity)")
    }

    // MARK: - Fingerprints

    private func tailHash(of url: URL, endingAt offset: Int64) throws -> String {
        guard offset > 0, let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let count = min(Int64(Self.fingerprintByteCount), offset)
        try handle.seek(toOffset: UInt64(offset - count))
        let data = try handle.read(upToCount: Int(count)) ?? Data()
        return Self.sha256(data)
    }

    private func sampledHash(of url: URL, size: Int64) throws -> String {
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let count = min(Int64(Self.fingerprintByteCount), size)
        let first = try handle.read(upToCount: Int(count)) ?? Data()
        var sample = first
        if size > count {
            try handle.seek(toOffset: UInt64(size - count))
            sample.append(try handle.read(upToCount: Int(count)) ?? Data())
        }
        return Self.sha256(sample)
    }

    private nonisolated static func endpointKey(_ endpoint: String) -> String {
        sha256(endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private nonisolated static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func fileIdentifier(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let data = value as? Data { return data.base64EncodedString() }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private nonisolated static func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private nonisolated static func encodeCursor(_ cursor: OpenCodeCursor) -> String {
        guard let data = try? JSONEncoder().encode(cursor) else { return "" }
        return data.base64EncodedString()
    }

    private nonisolated static func decodeCursor(_ value: String?) -> OpenCodeCursor? {
        guard let value, let data = Data(base64Encoded: value) else { return nil }
        return try? JSONDecoder().decode(OpenCodeCursor.self, from: data)
    }

    private nonisolated static func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private nonisolated static func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }
}

private nonisolated struct DiscoveredFile: Sendable {
    let source: BlogUsageIndexedSource
    let url: URL
    let fileIdentifier: String?
    let fileSize: Int64
    let modificationDate: Date
}

private nonisolated struct FileProcessResult: Sendable {
    let bytesRead: Int
    let filesProcessed: Int
    let recordsProcessed: Int
    let changedRecords: Int
    let maximumBufferedBytes: Int
    let isComplete: Bool

    static let unreadable = FileProcessResult(
        bytesRead: 0,
        filesProcessed: 0,
        recordsProcessed: 0,
        changedRecords: 0,
        maximumBufferedBytes: 0,
        isComplete: true
    )
}

private nonisolated struct MutableMetrics {
    var bytesRead = 0
    var filesProcessed = 0
    var filesSkipped = 0
    var recordsProcessed = 0
    var changedRecords = 0
    var cacheRows = 0
    var maximumBufferedBytes = 0
    var remainingSources = 0

    init(_ openCode: OpenCodeProcessResult) {
        bytesRead = openCode.bytesRead
        recordsProcessed = openCode.recordsProcessed
        changedRecords = openCode.changedRecords
        maximumBufferedBytes = openCode.maximumBufferedBytes
    }

    mutating func merge(_ value: FileProcessResult, countFile: Bool) {
        bytesRead += value.bytesRead
        if countFile {
            filesProcessed += value.filesProcessed
        }
        recordsProcessed += value.recordsProcessed
        changedRecords += value.changedRecords
        maximumBufferedBytes = max(maximumBufferedBytes, value.maximumBufferedBytes)
    }

    var result: BlogUsageIndexResult {
        BlogUsageIndexResult(
            bytesRead: bytesRead,
            filesProcessed: filesProcessed,
            filesSkipped: filesSkipped,
            recordsProcessed: recordsProcessed,
            changedRecords: changedRecords,
            cacheRows: cacheRows,
            maximumBufferedBytes: maximumBufferedBytes,
            remainingSources: remainingSources
        )
    }
}

private nonisolated struct OpenCodeCursor: Codable, Sendable, Equatable {
    let value: String
    let id: String
}

private nonisolated struct OpenCodeSchema: Sendable {
    let idExpression: String
    let updatedColumn: String
}

private nonisolated enum OpenCodeDirection: Sendable {
    case forward(after: OpenCodeCursor)
    case backward(before: OpenCodeCursor?)
}

private nonisolated struct OpenCodeProcessResult: Sendable {
    var bytesRead: Int
    var recordsProcessed: Int
    var changedRecords: Int
    var maximumBufferedBytes: Int
    var lastCursor: OpenCodeCursor?
    var exhausted: Bool

    static let empty = OpenCodeProcessResult(
        bytesRead: 0,
        recordsProcessed: 0,
        changedRecords: 0,
        maximumBufferedBytes: 0,
        lastCursor: nil,
        exhausted: false
    )

    mutating func merge(_ other: OpenCodeProcessResult) {
        bytesRead += other.bytesRead
        recordsProcessed += other.recordsProcessed
        changedRecords += other.changedRecords
        maximumBufferedBytes = max(maximumBufferedBytes, other.maximumBufferedBytes)
        lastCursor = other.lastCursor ?? lastCursor
        exhausted = other.exhausted
    }
}
#endif
