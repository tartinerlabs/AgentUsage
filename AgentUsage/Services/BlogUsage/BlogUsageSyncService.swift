//
//  BlogUsageSyncService.swift
//  AgentUsage
//

#if os(macOS)
import CryptoKit
import Foundation
import SQLite3

nonisolated struct BlogUsageEvent: Sendable, Equatable {
    let id: String
    let timestamp: Date
    let agent: String
    let provider: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let reasoningTokens: Int
}

nonisolated struct BlogUsageIngestRow: Codable, Sendable, Equatable {
    let date: String
    let agent: String
    let provider: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let costUsd: String?
    let messages: Int

    enum CodingKeys: String, CodingKey {
        case date
        case agent
        case provider
        case model
        case inputTokens
        case outputTokens
        case cacheReadTokens
        case cacheWriteTokens
        case reasoningTokens
        case totalTokens
        case costUsd
        case messages
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(agent, forKey: .agent)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encode(cacheWriteTokens, forKey: .cacheWriteTokens)
        try container.encode(reasoningTokens, forKey: .reasoningTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(messages, forKey: .messages)

        if let costUsd {
            try container.encode(costUsd, forKey: .costUsd)
        } else {
            try container.encodeNil(forKey: .costUsd)
        }
    }
}

nonisolated struct BlogUsageIngestPayload: Codable, Sendable, Equatable {
    let rows: [BlogUsageIngestRow]
}

nonisolated enum BlogUsageSyncState: String, Codable, Sendable {
    case never
    case skipped
    case syncing
    case success
    case failed
}

nonisolated struct BlogUsageSyncStatus: Codable, Sendable, Equatable {
    let state: BlogUsageSyncState
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let message: String

    static let never = BlogUsageSyncStatus(
        state: .never,
        lastAttemptAt: nil,
        lastSuccessAt: nil,
        message: "Not synced yet"
    )
}

nonisolated struct BlogUsageSyncSettings: Sendable, Equatable {
    var isEnabled: Bool
    var endpointURLString: String
    var token: String
    var status: BlogUsageSyncStatus
}

nonisolated enum BlogUsageSyncError: LocalizedError, Sendable {
    case invalidEndpoint
    case missingToken
    case unauthorized
    case serverError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid blog usage endpoint URL."
        case .missingToken:
            return "BLOG_MCP_AUTH_TOKEN is missing."
        case .unauthorized:
            return "Blog usage sync is unauthorized."
        case .serverError(let status, let detail):
            return Self.serverErrorDescription(status: status, detail: detail)
        case .invalidResponse:
            return "Blog usage sync received an invalid response."
        }
    }

    private nonisolated static func serverErrorDescription(status: Int, detail: String) -> String {
        guard !detail.isEmpty else {
            return "Blog usage sync failed with HTTP \(status)."
        }

        if let compact = compactValidationDescription(from: detail) {
            return compact
        }

        let maxDetailLength = 240
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeDetail = trimmed.count > maxDetailLength
            ? "\(trimmed.prefix(maxDetailLength))..."
            : trimmed
        return "Blog usage sync failed with HTTP \(status): \(safeDetail)"
    }

    private nonisolated static func compactValidationDescription(from detail: String) -> String? {
        guard let data = detail.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]],
              !errors.isEmpty else {
            return nil
        }

        let rowFields = errors.compactMap { error -> (row: Int, field: String)? in
            guard let field = error["field"] as? String else { return nil }
            let parts = field.split(separator: ".").map(String.init)
            guard parts.count >= 3,
                  parts[0] == "rows",
                  let row = Int(parts[1]) else {
                return nil
            }
            return (row, parts[2])
        }

        guard !rowFields.isEmpty else {
            return "Blog usage sync failed: validation failed for \(errors.count) field\(errors.count == 1 ? "" : "s")."
        }

        let fields = Set(rowFields.map(\.field))
        let rows = Set(rowFields.map(\.row))

        if fields.count == 1, let field = fields.first {
            return "Blog usage sync failed: invalid \(field) in \(rows.count) row\(rows.count == 1 ? "" : "s")."
        }

        return "Blog usage sync failed: invalid input in \(rows.count) row\(rows.count == 1 ? "" : "s")."
    }
}

nonisolated struct BlogUsageAggregator {
    private nonisolated struct Key: Hashable {
        let date: String
        let agent: String
        let provider: String
        let model: String
    }

    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    nonisolated init(calendar: Calendar = .current) {
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    nonisolated func aggregate(_ events: [BlogUsageEvent]) -> [BlogUsageIngestRow] {
        var grouped: [Key: [BlogUsageEvent]] = [:]

        for event in events {
            let date = dateFormatter.string(from: calendar.startOfDay(for: event.timestamp))
            let key = Key(date: date, agent: event.agent, provider: event.provider, model: event.model)
            grouped[key, default: []].append(event)
        }

        return grouped.map { key, events in
            let inputTokens = events.reduce(0) { $0 + $1.inputTokens }
            let outputTokens = events.reduce(0) { $0 + $1.outputTokens }
            let cacheReadTokens = events.reduce(0) { $0 + $1.cacheReadTokens }
            let cacheWriteTokens = events.reduce(0) { $0 + $1.cacheWriteTokens }
            let reasoningTokens = events.reduce(0) { $0 + $1.reasoningTokens }
            let totalTokens = inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens + reasoningTokens
            let costUsd = ModelPricing.costUSD(
                provider: key.provider,
                model: key.model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheWriteTokens: cacheWriteTokens,
                reasoningTokens: reasoningTokens
            ).map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) }

            return BlogUsageIngestRow(
                date: key.date,
                agent: key.agent,
                provider: key.provider,
                model: key.model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheWriteTokens: cacheWriteTokens,
                reasoningTokens: reasoningTokens,
                totalTokens: totalTokens,
                costUsd: costUsd,
                messages: events.count
            )
        }
        .sorted {
            ($0.date, $0.agent, $0.provider, $0.model) < ($1.date, $1.agent, $1.provider, $1.model)
        }
    }
}

nonisolated struct BlogUsageSourceParser {
    let fileManager: FileManager
    let homeDirectory: URL
    let environment: [String: String]
    let now: @Sendable () -> Date

    private let isoFormatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated init(
        fileManager: FileManager = .default,
        // Real home, not the sandbox container home. Under the App Sandbox
        // `homeDirectoryForCurrentUser` returns the container, whose `.claude`/`.codex`
        // paths do not exist; `Constants.realHomeDirectory` resolves the true home that
        // the user's security-scoped folder grants make readable.
        homeDirectory: URL = Constants.realHomeDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.now = now
    }

    nonisolated func parseAllSources() throws -> [BlogUsageEvent] {
        try parseClaudeEvents() + parseCodexEvents() + parseOpenCodeEvents()
    }

    nonisolated func parseClaudeEvents() throws -> [BlogUsageEvent] {
        let roots = [
            homeDirectory.appendingPathComponent(".claude/projects"),
            homeDirectory.appendingPathComponent(".config/claude/projects")
        ]
        let files = try roots.flatMap { try jsonlFiles(in: $0) }
        var seen = Set<String>()
        var events: [BlogUsageEvent] = []

        for file in files {
            for line in try lines(in: file) {
                guard let parsed = parseClaudeLine(Data(line.utf8)) else { continue }
                guard seen.insert(parsed.dedupeID).inserted else { continue }
                events.append(parsed.event)
            }
        }

        return events
    }

    nonisolated func parseCodexEvents() throws -> [BlogUsageEvent] {
        let roots = [
            homeDirectory.appendingPathComponent(".codex/sessions"),
            homeDirectory.appendingPathComponent(".codex/archived_sessions")
        ]
        let files = try roots.flatMap { try jsonlFiles(in: $0) }
        var events: [BlogUsageEvent] = []

        for file in files {
            var currentModel = "unknown"
            for line in try lines(in: file) {
                if let event = parseCodexLine(Data(line.utf8), currentModel: &currentModel) {
                    events.append(event)
                }
            }
        }

        return events
    }

    nonisolated func parseCodexLine(_ data: Data, currentModel: inout String) -> BlogUsageEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }

        if let model = payload["model"] as? String, !model.isEmpty {
            currentModel = model
        }

        guard let type = payload["type"] as? String,
              type == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any],
              let timestamp = parseTimestamp(from: json) ?? parseTimestamp(from: payload) else {
            return nil
        }

        let inputTokensRaw = intValue(usage["input_tokens"])
        let cachedInputTokens = intValue(usage["cached_input_tokens"])
            + intValue((usage["input_tokens_details"] as? [String: Any])?["cached_tokens"])
        let outputTokensRaw = intValue(usage["output_tokens"])
        let reasoningTokens = intValue(usage["reasoning_output_tokens"])
            + intValue((usage["output_tokens_details"] as? [String: Any])?["reasoning_tokens"])
        let eventID = stringValue(payload["id"])
            ?? stringValue(json["id"])
            ?? stableHash(data)

        return BlogUsageEvent(
            id: "codex-\(eventID)",
            timestamp: timestamp,
            agent: "codex",
            provider: "openai",
            model: currentModel,
            inputTokens: max(0, inputTokensRaw - cachedInputTokens),
            outputTokens: max(0, outputTokensRaw - reasoningTokens),
            cacheReadTokens: max(0, cachedInputTokens),
            cacheWriteTokens: 0,
            reasoningTokens: max(0, reasoningTokens)
        )
    }

    nonisolated func parseOpenCodeEvents() throws -> [BlogUsageEvent] {
        let databaseURL = openCodeDatabaseURL()
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }
        return try OpenCodeDatabaseReader(databaseURL: databaseURL, now: now).readEvents()
    }

    nonisolated func parseClaudeLine(_ data: Data) -> (event: BlogUsageEvent, dedupeID: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any],
              let timestamp = parseTimestamp(from: json) else {
            return nil
        }
        guard model != "<synthetic>" else { return nil }

        let dedupeID = stringValue(message["id"])
            ?? stringValue(json["requestId"])
            ?? stringValue(json["request_id"])
            ?? stringValue(json["uuid"])
            ?? stableHash(data)

        let event = BlogUsageEvent(
            id: "claude-\(dedupeID)",
            timestamp: timestamp,
            agent: "claude",
            provider: "anthropic",
            model: model,
            inputTokens: intValue(usage["input_tokens"]),
            outputTokens: intValue(usage["output_tokens"]),
            cacheReadTokens: intValue(usage["cache_read_input_tokens"]),
            cacheWriteTokens: intValue(usage["cache_creation_input_tokens"]),
            reasoningTokens: 0
        )

        return (event, dedupeID)
    }

    nonisolated func parseOpenCodeMessageData(
        _ data: Data,
        fallbackID: String,
        timestamp: Date
    ) -> BlogUsageEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let role = stringValue(json["role"]) ?? stringValue(json["type"])
        guard role == nil || role == "assistant" else { return nil }

        guard let tokens = (json["tokens"] as? [String: Any])
                ?? (json["token"] as? [String: Any])
                ?? (json["usage"] as? [String: Any]) else {
            return nil
        }

        let cache = tokens["cache"] as? [String: Any]
        let reasoningTokens = intValue(tokens["reasoning"])
        let outputTokens = max(0, intValue(tokens["output"]) - reasoningTokens)
        let provider = stringValue(json["providerID"])
            ?? stringValue(json["providerId"])
            ?? stringValue(json["provider"])
            ?? "unknown"
        let model = stringValue(json["modelID"])
            ?? stringValue(json["modelId"])
            ?? stringValue(json["model"])
            ?? "unknown"
        let eventID = stringValue(json["id"]) ?? fallbackID

        return BlogUsageEvent(
            id: "opencode-\(eventID)",
            timestamp: parseTimestamp(from: json) ?? timestamp,
            agent: "opencode",
            provider: provider,
            model: model,
            inputTokens: intValue(tokens["input"]),
            outputTokens: outputTokens,
            cacheReadTokens: intValue(cache?["read"]),
            cacheWriteTokens: intValue(cache?["write"]),
            reasoningTokens: max(0, reasoningTokens)
        )
    }

    nonisolated func openCodeDatabaseURL() -> URL {
        if let xdgDataHome = environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            return URL(fileURLWithPath: xdgDataHome).appendingPathComponent("opencode/opencode.db")
        }
        return homeDirectory.appendingPathComponent(".local/share/opencode/opencode.db")
    }

    private nonisolated func jsonlFiles(in root: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private nonisolated func lines(in url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        return content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private nonisolated func parseTimestamp(from json: [String: Any]) -> Date? {
        if let time = json["time"] as? [String: Any],
           let created = dateValue(time["created"]) {
            return created
        }

        let candidates = [
            json["timestamp"],
            json["createdAt"],
            json["created_at"],
            json["time"],
            json["date"]
        ]

        for candidate in candidates {
            if let date = dateValue(candidate) {
                return date
            }
        }
        return nil
    }

    private nonisolated func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let string = value as? String {
            if let date = isoFormatterWithFraction.date(from: string) ?? isoFormatter.date(from: string) {
                return date
            }
            if let seconds = Double(string) {
                return epochDate(seconds)
            }
        }
        if let seconds = value as? Double {
            return epochDate(seconds)
        }
        if let seconds = value as? Int {
            return epochDate(Double(seconds))
        }
        if let number = value as? NSNumber {
            return epochDate(number.doubleValue)
        }
        return nil
    }

    private nonisolated func epochDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }

    private nonisolated func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value) ?? 0
        }
        return 0
    }

    private nonisolated func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private nonisolated func stableHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct OpenCodeDatabaseReader {
        let databaseURL: URL
        let now: @Sendable () -> Date

        func readEvents() throws -> [BlogUsageEvent] {
            var database: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY
            guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
                defer { sqlite3_close(database) }
                return []
            }
            defer { sqlite3_close(database) }

            let columns = try messageColumns(database: database)
            guard columns.contains("data") else { return [] }

            let idColumn = firstExistingColumn(["id", "messageID", "message_id"], in: columns)
            let timestampColumn = firstExistingColumn(["createdAt", "created_at", "time", "timestamp", "created"], in: columns)
            let selectColumns = ["data", idColumn, timestampColumn].compactMap { $0 }
            let query = "SELECT \(selectColumns.map(quoteIdentifier).joined(separator: ", ")) FROM message"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            let parser = BlogUsageSourceParser(now: now)
            var seen = Set<String>()
            var events: [BlogUsageEvent] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let dataText = columnString(statement, index: 0),
                      let data = dataText.data(using: .utf8) else {
                    continue
                }

                let fallbackID = idColumn == nil ? parser.stableHash(data) : (columnString(statement, index: 1) ?? parser.stableHash(data))
                let timestampIndex = idColumn == nil ? 1 : 2
                let timestamp = timestampColumn == nil ? now() : parser.dateValue(columnString(statement, index: Int32(timestampIndex))) ?? now()

                guard let event = parser.parseOpenCodeMessageData(data, fallbackID: fallbackID, timestamp: timestamp) else {
                    continue
                }
                guard seen.insert(event.id).inserted else { continue }
                events.append(event)
            }

            return events
        }

        private func messageColumns(database: OpaquePointer) throws -> Set<String> {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "PRAGMA table_info(message)", -1, &statement, nil) == SQLITE_OK, let statement else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            var columns = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = columnString(statement, index: 1) {
                    columns.insert(name)
                }
            }
            return columns
        }

        private func firstExistingColumn(_ candidates: [String], in columns: Set<String>) -> String? {
            candidates.first { columns.contains($0) }
        }

        private func quoteIdentifier(_ identifier: String) -> String {
            "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        private func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let text = sqlite3_column_text(statement, index) else {
                return nil
            }
            return String(cString: text)
        }
    }
}

nonisolated protocol BlogUsageSyncPosting: Sendable {
    nonisolated func post(rows: [BlogUsageIngestRow], endpoint: URL, token: String) async throws
}

nonisolated struct BlogUsageSyncClient: BlogUsageSyncPosting {
    private let session: URLSession
    private let encoder: JSONEncoder

    nonisolated init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
    }

    nonisolated func post(rows: [BlogUsageIngestRow], endpoint: URL, token: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.httpBody = try encoder.encode(BlogUsageIngestPayload(rows: rows))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlogUsageSyncError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw BlogUsageSyncError.unauthorized
        default:
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw BlogUsageSyncError.serverError(httpResponse.statusCode, detail)
        }
    }
}

actor BlogUsageSyncService {
    static let shared = BlogUsageSyncService()

    nonisolated static let defaultEndpointURLString = "https://ruchern.dev/api/usage/ingest"
    private static let enabledKey = "blogUsageSyncEnabled"
    private static let endpointKey = "blogUsageSyncEndpointURL"
    private static let statusKey = "blogUsageSyncStatus"
    private static let defaultKeychainAccount = "blog-usage-sync-token"
    private static let throttleInterval: TimeInterval = 5 * 60

    private let indexer: any BlogUsageIndexing
    private let client: any BlogUsageSyncPosting
    private let defaults: UserDefaults
    private let keychainAccount: String
    private let oauthProvider: (any BlogAccessTokenProviding)?
    private let now: @Sendable () -> Date
    private var inFlightTask: Task<BlogUsageSyncStatus, Never>?

    init(
        indexer: any BlogUsageIndexing = BlogUsageSourceIndexer(),
        client: any BlogUsageSyncPosting = BlogUsageSyncClient(),
        defaults: UserDefaults = .standard,
        keychainAccount: String = BlogUsageSyncService.defaultKeychainAccount,
        oauthProvider: (any BlogAccessTokenProviding)? = BlogOAuthService.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.indexer = indexer
        self.client = client
        self.defaults = defaults
        self.keychainAccount = keychainAccount
        self.oauthProvider = oauthProvider
        self.now = now
    }

    func settings() -> BlogUsageSyncSettings {
        BlogUsageSyncSettings(
            isEnabled: isEnabled,
            endpointURLString: endpointURLString,
            token: loadTokenFromKeychain() ?? "",
            status: status
        )
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled {
            updateStatus(.skipped, message: "Blog usage sync is disabled")
        }
    }

    func setEndpointURLString(_ endpointURLString: String) {
        defaults.set(endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.endpointKey)
    }

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteTokenFromKeychain()
        } else {
            do {
                try saveTokenToKeychain(trimmed)
            } catch {
                updateStatus(.failed, message: "Failed to save BLOG_MCP_AUTH_TOKEN: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Token storage
    //
    // The token lives in the data-protection keychain, reached in-process through
    // `KeychainHelper`. Access there is granted by the `keychain-access-groups`
    // entitlement, and no per-item ACL exists — so nothing can trigger the "wants to
    // change access permissions" prompt.
    //
    // This deliberately does not use the `/usr/bin/security` CLI. Writing through it
    // required `-T` to name a trusted application, and modifying an item's ACL is gated
    // separately from reading it, trusting no application by default — so every write
    // re-prompted for the login password. Only Claude Code's *shared* keychain item
    // still goes through the CLI, because Claude Code owns that item's ACL; see
    // `MacOSCredentialService`.

    private func loadTokenFromKeychain() -> String? {
        guard let token = try? KeychainHelper.loadString(account: keychainAccount),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func saveTokenToKeychain(_ token: String) throws {
        try KeychainHelper.saveString(token, account: keychainAccount)
    }

    private func deleteTokenFromKeychain() {
        KeychainHelper.deleteString(account: keychainAccount)
    }

    func syncIfNeeded() async -> BlogUsageSyncStatus {
        await sync(mode: .passive)
    }

    func syncNow() async -> BlogUsageSyncStatus {
        await sync(mode: .manual)
    }

    private func sync(mode: SyncMode) async -> BlogUsageSyncStatus {
        if let inFlightTask {
            return await inFlightTask.value
        }

        let task = Task<BlogUsageSyncStatus, Never>(priority: mode.priority) {
            await self.performSync(mode: mode)
        }
        inFlightTask = task
        let result = await task.value
        inFlightTask = nil
        return result
    }

    private func performSync(mode: SyncMode) async -> BlogUsageSyncStatus {
        guard isEnabled else {
            return updateStatus(.skipped, message: "Blog usage sync is disabled")
        }

        // Prefer the OAuth access token (refreshed if needed); fall back to the static
        // BLOG_MCP_AUTH_TOKEN when not signed in.
        let oauthToken = try? await oauthProvider?.validAccessToken()
        let token = (oauthToken?.isEmpty == false ? oauthToken! : loadTokenFromKeychain()) ?? ""
        guard !token.isEmpty else {
            return updateStatus(.skipped, message: "Sign in to the blog or set BLOG_MCP_AUTH_TOKEN")
        }

        guard let endpoint = URL(string: endpointURLString), endpoint.scheme != nil else {
            return updateStatus(.failed, message: BlogUsageSyncError.invalidEndpoint.localizedDescription)
        }

        if mode == .passive,
           let lastAttempt = status.lastAttemptAt,
           now().timeIntervalSince(lastAttempt) < Self.throttleInterval {
            // Do not restamp `lastAttemptAt` here: passive sync fires every refresh
            // tick, so restamping on skip would perpetually reset the throttle window
            // and passive sync could never run again.
            return updateStatus(
                .skipped,
                message: "Blog usage sync skipped; last attempt was less than five minutes ago",
                countsAsAttempt: false
            )
        }

        updateStatus(.syncing, message: "Syncing blog usage")

        do {
            await LiteLLMPricingCache.shared.refreshIfNeeded()
            let indexResult = try await indexer.index(maximumBytes: mode.byteBudget)
            let revision = try await indexer.revision()
            let uploadedRevision = try await indexer.uploadedRevision(endpoint: endpoint.absoluteString)
            guard revision > uploadedRevision else {
                return updateStatus(
                    .success,
                    message: noChangesMessage(indexResult),
                    success: true
                )
            }

            let rows = try await indexer.rows()
            guard !rows.isEmpty else {
                try await indexer.markUploaded(revision: revision, endpoint: endpoint.absoluteString)
                return updateStatus(
                    .success,
                    message: indexResult.isBackfillInProgress
                        ? noChangesMessage(indexResult)
                        : "No usage rows to sync",
                    success: true
                )
            }

            try await client.post(rows: rows, endpoint: endpoint, token: token)
            try await indexer.markUploaded(revision: revision, endpoint: endpoint.absoluteString)
            let suffix = indexResult.isBackfillInProgress
                ? "; indexing history (\(indexResult.remainingSources) source\(indexResult.remainingSources == 1 ? "" : "s") remaining)"
                : ""
            return updateStatus(
                .success,
                message: "Synced \(rows.count) usage row\(rows.count == 1 ? "" : "s")\(suffix)",
                success: true
            )
        } catch {
            return updateStatus(.failed, message: error.localizedDescription)
        }
    }

    private func noChangesMessage(_ result: BlogUsageIndexResult) -> String {
        guard result.isBackfillInProgress else { return "No new usage rows to sync" }
        return "Indexing usage history (\(result.remainingSources) source\(result.remainingSources == 1 ? "" : "s") remaining)"
    }

    @discardableResult
    private func updateStatus(
        _ state: BlogUsageSyncState,
        message: String,
        success: Bool = false,
        countsAsAttempt: Bool = true
    ) -> BlogUsageSyncStatus {
        let currentStatus = status
        let updated = BlogUsageSyncStatus(
            state: state,
            lastAttemptAt: countsAsAttempt ? now() : currentStatus.lastAttemptAt,
            lastSuccessAt: success ? now() : currentStatus.lastSuccessAt,
            message: message
        )

        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.statusKey)
        }
        return updated
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    private var endpointURLString: String {
        let saved = defaults.string(forKey: Self.endpointKey)
        return saved?.isEmpty == false ? saved! : Self.defaultEndpointURLString
    }

    private var status: BlogUsageSyncStatus {
        guard let data = defaults.data(forKey: Self.statusKey),
              let decoded = try? JSONDecoder().decode(BlogUsageSyncStatus.self, from: data) else {
            return .never
        }
        return decoded
    }

    private enum SyncMode: Sendable {
        case passive
        case manual

        var byteBudget: Int {
            switch self {
            case .passive: BlogUsageSourceIndexer.passiveByteBudget
            case .manual: BlogUsageSourceIndexer.manualByteBudget
            }
        }

        var priority: TaskPriority {
            switch self {
            case .passive: .utility
            case .manual: .userInitiated
            }
        }
    }
}
#endif
