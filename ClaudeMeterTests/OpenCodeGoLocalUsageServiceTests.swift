//
//  OpenCodeGoLocalUsageServiceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import ClaudeMeter
import ClaudeMeterKit

@Suite("OpenCode Go Local Usage Service")
struct OpenCodeGoLocalUsageServiceTests {
    private typealias Row = OpenCodeGoLocalUsageService.UsageRow

    // MARK: - Snapshot math

    @Test func computesWindowPercentsTypesAndOrder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        // One $3 message 1 hour ago: inside session, week, and month.
        let rows = [Row(createdMs: nowMs - 3_600_000, cost: 3.0)]

        let snapshot = OpenCodeGoLocalUsageService.makeSnapshot(rows: rows, now: now)

        #expect(snapshot.provider == .openCode)
        #expect(snapshot.planName == "Go")
        #expect(snapshot.fetchedAt == now)
        #expect(snapshot.windows.map(\.windowType) == [.openCodeGoFiveHour, .openCodeGoWeekly, .openCodeGoMonthly])
        // 3 / 12 = 25%, 3 / 30 = 10%, 3 / 60 = 5%
        #expect(snapshot.windows[0].utilization == 25.0)
        #expect(snapshot.windows[1].utilization == 10.0)
        #expect(snapshot.windows[2].utilization == 5.0)
    }

    @Test func rollingResetIsFiveHoursAfterOldestInWindowMessage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let oldestMs = nowMs - 3_600_000  // 1h ago
        let rows = [
            Row(createdMs: oldestMs, cost: 1.0),
            Row(createdMs: nowMs - 600_000, cost: 1.0)  // 10m ago
        ]

        let snapshot = OpenCodeGoLocalUsageService.makeSnapshot(rows: rows, now: now)
        let expectedReset = Date(timeIntervalSince1970: Double(oldestMs) / 1000 + 5 * 60 * 60)

        #expect(snapshot.windows[0].resetsAt == expectedReset)
    }

    @Test func percentIsCappedAtOneHundred() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        // $20 in the session window exceeds the $12 limit.
        let rows = [Row(createdMs: nowMs - 60_000, cost: 20.0)]

        let snapshot = OpenCodeGoLocalUsageService.makeSnapshot(rows: rows, now: now)

        #expect(snapshot.windows[0].utilization == 100.0)
    }

    @Test func messagesOutsideSessionExcludedFromRollingWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        // 6 hours ago: outside the 5h rolling window, but same week.
        let rows = [Row(createdMs: nowMs - Int64(6 * 60 * 60 * 1000), cost: 6.0)]

        let snapshot = OpenCodeGoLocalUsageService.makeSnapshot(rows: rows, now: now)

        #expect(snapshot.windows[0].utilization == 0.0)          // nothing in session
        #expect(snapshot.windows[1].utilization == 20.0)         // 6 / 30 weekly
        // Rolling reset falls back to 5h from now when the window is empty.
        #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(5 * 60 * 60))
    }

    // MARK: - Auth detection

    @Test func hasAuthKeyTrueWhenOpenCodeGoKeyPresent() throws {
        let url = try Self.writeAuthJSON(#"{"opencode-go":{"type":"api","key":"secret-key-value"}}"#)
        #expect(OpenCodeGoLocalUsageService.hasAuthKey(at: url))
    }

    @Test func hasAuthKeyFalseWhenKeyMissingOrEmpty() throws {
        let missing = try Self.writeAuthJSON(#"{"openai":{"type":"oauth","access":"x"}}"#)
        let empty = try Self.writeAuthJSON(#"{"opencode-go":{"type":"api","key":"   "}}"#)

        #expect(!OpenCodeGoLocalUsageService.hasAuthKey(at: missing))
        #expect(!OpenCodeGoLocalUsageService.hasAuthKey(at: empty))
        #expect(!OpenCodeGoLocalUsageService.hasAuthKey(at: URL(fileURLWithPath: "/no/such/auth.json")))
    }

    // MARK: - End-to-end against a fixture database

    @Test func fetchSnapshotReadsMessageOnlyDatabase() async throws {
        let root = try Self.temporaryDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let auth = root.appendingPathComponent("auth.json")
        try Self.writeAuth(at: auth)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try Self.createMessageDatabase(at: db, includePartTable: false, messages: [
            .init(id: "m1", createdMs: nowMs - 3_600_000, cost: 6.0, providerID: "opencode-go", role: "assistant"),
            // Noise that must be ignored: wrong provider, wrong role.
            .init(id: "m2", createdMs: nowMs - 3_600_000, cost: 99.0, providerID: "openai", role: "assistant"),
            .init(id: "m3", createdMs: nowMs - 3_600_000, cost: 99.0, providerID: "opencode-go", role: "user")
        ], parts: [])

        let service = OpenCodeGoLocalUsageService(databaseURLs: [db], authURL: auth)
        let snapshot = try #require(try await service.fetchSnapshot())

        #expect(snapshot.provider == .openCode)
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows[0].utilization == 50.0)  // 6 / 12, noise excluded
    }

    @Test func fetchSnapshotUnionsStepFinishPartsWhenPartTableExists() async throws {
        let root = try Self.temporaryDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let auth = root.appendingPathComponent("auth.json")
        try Self.writeAuth(at: auth)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // The message itself has no cost → its spend lives on a step-finish part.
        try Self.createMessageDatabase(at: db, includePartTable: true, messages: [
            .init(id: "m1", createdMs: nowMs - 3_600_000, cost: nil, providerID: "opencode-go", role: "assistant")
        ], parts: [
            .init(id: "p1", messageID: "m1", createdMs: nowMs - 3_600_000, cost: 9.0, type: "step-finish")
        ])

        let service = OpenCodeGoLocalUsageService(databaseURLs: [db], authURL: auth)
        let snapshot = try #require(try await service.fetchSnapshot())

        #expect(snapshot.windows[0].utilization == 75.0)  // 9 / 12 from the part
    }

    @Test func fetchSnapshotReturnsNilWhenNoDatabase() async throws {
        let service = OpenCodeGoLocalUsageService(
            databaseURLs: [URL(fileURLWithPath: "/no/such/opencode.db")],
            authURL: URL(fileURLWithPath: "/no/such/auth.json")
        )
        #expect(try await service.fetchSnapshot() == nil)
    }

    @Test func fetchSnapshotReturnsNilWhenSignedInButNoUsage() async throws {
        let root = try Self.temporaryDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let auth = root.appendingPathComponent("auth.json")
        try Self.writeAuth(at: auth)
        try Self.createMessageDatabase(at: db, includePartTable: false, messages: [], parts: [])

        let service = OpenCodeGoLocalUsageService(databaseURLs: [db], authURL: auth)
        #expect(try await service.fetchSnapshot() == nil)
    }

    // MARK: - Fixtures

    private struct MessageFixture {
        let id: String
        let createdMs: Int64
        let cost: Double?
        let providerID: String
        let role: String
    }

    private struct PartFixture {
        let id: String
        let messageID: String
        let createdMs: Int64
        let cost: Double
        let type: String
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeGoLocalUsageServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeAuth(at url: URL) throws {
        try #"{"opencode-go":{"type":"api","key":"test-key"}}"#.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeAuthJSON(_ json: String) throws -> URL {
        let url = try temporaryDirectory().appendingPathComponent("auth.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func createMessageDatabase(
        at url: URL,
        includePartTable: Bool,
        messages: [MessageFixture],
        parts: [PartFixture]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw TestError.sqliteOpenFailed
        }
        defer { sqlite3_close(database) }

        try exec(database, """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            data TEXT NOT NULL
        )
        """)
        if includePartTable {
            try exec(database, """
            CREATE TABLE part (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                data TEXT NOT NULL
            )
            """)
        }

        for message in messages {
            var payload: [String: Any] = [
                "providerID": message.providerID,
                "role": message.role,
                "time": ["created": message.createdMs]
            ]
            if let cost = message.cost { payload["cost"] = cost }
            let json = try jsonString(payload)
            try exec(database, """
            INSERT INTO message (id, session_id, time_created, data)
            VALUES ('\(message.id)', 's1', \(message.createdMs), '\(escape(json))')
            """)
        }

        for part in parts {
            let json = try jsonString([
                "type": part.type,
                "cost": part.cost,
                "time": ["created": part.createdMs]
            ])
            try exec(database, """
            INSERT INTO part (id, message_id, session_id, time_created, data)
            VALUES ('\(part.id)', '\(part.messageID)', 's1', \(part.createdMs), '\(escape(json))')
            """)
        }
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestError.sqliteExecFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else { throw TestError.encodingFailed }
        return string
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private enum TestError: Error {
        case sqliteOpenFailed
        case sqliteExecFailed(String)
        case encodingFailed
    }
}
#endif
