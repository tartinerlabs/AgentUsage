#if os(macOS)
import Foundation
import SQLite3
import AgentUsageKit

nonisolated struct GoogleUsageCredentials: Sendable, Equatable {
    let accessToken: String
    var expiresAt: Date?
}

/// Reuses the tools' local Google sessions. Never writes their credential stores.
nonisolated enum GoogleUsageAuth {
    static func gemini(at url: URL) -> GoogleUsageCredentials? {
        let settings = url.deletingLastPathComponent().appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: settings),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let security = json["security"] as? [String: Any],
           let auth = security["auth"] as? [String: Any],
           let type = auth["selectedType"] as? String, type != "oauth-personal" {
            return nil // API-key and Vertex authentication have different quotas.
        }
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else { return nil }
        return GoogleUsageCredentials(
            accessToken: token,
            expiresAt: (json["expiry_date"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000) }
        )
    }

    static func antigravity(at urls: [URL]) -> GoogleUsageCredentials? {
        for url in urls {
            var database: OpaquePointer?
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let database else {
                if let database { sqlite3_close(database) }
                continue
            }
            defer { sqlite3_close(database) }
            sqlite3_busy_timeout(database, 500)
            // Read through WAL so a currently signed-in IDE is visible.
            for key in ["antigravityUnifiedStateSync.oauthToken", "jetskiStateSync.agentManagerInitState", "antigravityAuthStatus"] {
                var statement: OpaquePointer?
                let query = "SELECT value FROM ItemTable WHERE key = ?"
                guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(statement) }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                _ = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
                guard sqlite3_step(statement) == SQLITE_ROW,
                      let text = sqlite3_column_text(statement, 0) else { continue }
                if let credentials = parseAntigravity(String(cString: text), key: key) { return credentials }
            }
        }
        return nil
    }

    static func parseAntigravity(_ value: String, key: String) -> GoogleUsageCredentials? {
        if key == "antigravityAuthStatus" {
            guard let json = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any],
                  let token = json["apiKey"] as? String, !token.isEmpty else { return nil }
            return GoogleUsageCredentials(accessToken: token)
        }
        guard let data = Data(base64Encoded: value) else { return nil }
        let tokenData: Data
        if key == "jetskiStateSync.agentManagerInitState" {
            guard let nested = protobufBytes(data, field: 6) else { return nil }
            tokenData = nested
        } else {
            // Unified state is Topic -> map entry -> Row -> base64 OAuthTokenInfo.
            // Older IDEs put the binary payload directly in the map entry.
            guard let entry = protobufValues(data, field: 1).first(where: {
                protobufBytes($0, field: 1).flatMap { String(data: $0, encoding: .utf8) } == "oauthTokenInfoSentinelKey"
            }), let row = protobufBytes(entry, field: 2) else { return nil }
            if let encoded = protobufBytes(row, field: 1).flatMap({ String(data: $0, encoding: .utf8) }),
               let decoded = Data(base64Encoded: encoded) {
                tokenData = decoded
            } else if let encoded = String(data: row, encoding: .utf8), let decoded = Data(base64Encoded: encoded) {
                tokenData = decoded
            } else { tokenData = row }
        }
        guard let rawToken = protobufBytes(tokenData, field: 1),
              let token = String(data: rawToken, encoding: .utf8), !token.isEmpty else { return nil }
        return GoogleUsageCredentials(accessToken: token)
    }

    /// Reads length-delimited protobuf fields with bounds checks; unknown fields are skipped.
    private static func protobufBytes(_ data: Data, field: UInt64) -> Data? {
        protobufValues(data, field: field).first
    }

    private static func protobufValues(_ data: Data, field: UInt64) -> [Data] {
        let bytes = Array(data)
        var offset = 0
        var result: [Data] = []
        func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard offset < bytes.count else { return nil }
                let byte = bytes[offset]; offset += 1
                if shift == 63 && byte > 1 { return nil }
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
            }
            return nil
        }
        while offset < bytes.count {
            guard let tag = varint(), tag >> 3 > 0 else { return [] }
            switch tag & 7 {
            case 0: guard varint() != nil else { return [] }
            case 1: guard bytes.count - offset >= 8 else { return [] }; offset += 8
            case 2:
                guard let rawLength = varint(), rawLength <= UInt64(bytes.count - offset) else { return [] }
                let length = Int(rawLength)
                if tag >> 3 == field { result.append(Data(bytes[offset..<(offset + length)])) }
                offset += length
            case 5: guard bytes.count - offset >= 4 else { return [] }; offset += 4
            default: return []
            }
        }
        return result
    }
}

/// Google Code Assist quota endpoints used by Gemini CLI and Antigravity.
/// Each tool owns its token renewal; credentials are reloaded on every refresh.
actor GoogleUsageService: ProviderUsageServiceProtocol {
    nonisolated let provider: Provider
    nonisolated enum UsageError: LocalizedError {
        case unauthorized(Provider)
        case forbidden(Provider)
        case invalidResponse
        case serverError(Int)
        case rateLimited(TimeInterval?)
        var errorDescription: String? {
            switch self {
            case .unauthorized(let provider): "Sign in again in \(provider.displayName), then refresh usage."
            case .forbidden(let provider): "Google has not granted this account access to \(provider.displayName) quotas."
            case .invalidResponse: "Google did not return usable model quotas."
            case .serverError(let code): "Google usage request failed (HTTP \(code))."
            case .rateLimited: "Google usage requests are temporarily rate limited."
            }
        }
    }

    private let loadCredentials: @Sendable () -> GoogleUsageCredentials?
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let now: @Sendable () -> Date
    private let projectID: String?

    init(
        provider: Provider,
        loadCredentials: (@Sendable () -> GoogleUsageCredentials?)? = nil,
        projectID: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        precondition(provider == .gemini || provider == .antigravity)
        self.provider = provider
        self.loadCredentials = loadCredentials ?? {
            provider == .gemini
                ? GoogleUsageAuth.gemini(at: Constants.geminiCredentialsURL)
                : GoogleUsageAuth.antigravity(at: Constants.antigravityStateDirectories.map { $0.appendingPathComponent("state.vscdb") })
        }
        self.projectID = projectID ?? (provider == .gemini
            ? ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]
                ?? ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT_ID"]
            : nil)
        self.now = now
        self.dataLoader = dataLoader
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let credentials = loadCredentials() else { return nil }
        if let expires = credentials.expiresAt, expires <= now() {
            throw UsageError.unauthorized(provider)
        }
        return try await fetchQuotas(credentials)
    }

    private func fetchQuotas(_ credentials: GoogleUsageCredentials) async throws -> ProviderUsageSnapshot {
        var body: [String: Any] = ["metadata": [
            "ideType": provider == .gemini ? "GEMINI_CLI" : "ANTIGRAVITY",
            "pluginType": "GEMINI", "platform": "PLATFORM_UNSPECIFIED",
        ]]
        if let projectID { body["cloudaicompanionProject"] = projectID }
        let account = try await request(method: "loadCodeAssist", token: credentials.accessToken, body: body)
        let managed = account["cloudaicompanionProject"]
        let project = projectID ?? (managed as? String) ?? ((managed as? [String: Any])?["id"] as? String)
        let tier = (account["paidTier"] as? [String: Any]) ?? (account["currentTier"] as? [String: Any])
        let planName = tier?["name"] as? String
        let quotaBody: [String: Any] = project.map { ["project": $0] } ?? [:]
        let quota: [String: Any]
        do {
            quota = try await request(
                method: provider == .gemini ? "retrieveUserQuota" : "fetchAvailableModels",
                token: credentials.accessToken, body: quotaBody
            )
        } catch UsageError.forbidden where provider == .antigravity {
            let fallback = try await request(method: "retrieveUserQuota", token: credentials.accessToken, body: quotaBody)
            return try Self.mapQuota(fallback, provider: provider, planName: planName, now: now())
        }
        let snapshot = try Self.mapQuota(quota, provider: provider, planName: planName, now: now())
        if provider == .antigravity, snapshot.windows.allSatisfy({ $0.utilization <= 0.1 }) {
            // Some accounts receive placeholder full allowances from the model
            // catalog. Verify those against the actual quota buckets.
            let verified = try await request(method: "retrieveUserQuota", token: credentials.accessToken, body: quotaBody)
            return try Self.mapQuota(verified, provider: provider, planName: planName, now: now())
        }
        return snapshot
    }

    private func request(method: String, token: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(method)") else {
            throw UsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = Constants.requestTimeout
        let (data, response) = try await dataLoader(request)
        try check(response)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw UsageError.invalidResponse }
        return json
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw UsageError.unauthorized(provider)
        case 403: throw UsageError.forbidden(provider)
        case 429: throw UsageError.rateLimited(http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        default: throw UsageError.serverError(http.statusCode)
        }
    }

    nonisolated static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    nonisolated static func mapQuota(_ body: [String: Any], provider: Provider, planName: String?, now: Date) throws -> ProviderUsageSnapshot {
        var rows: [(id: String, label: String, quota: [String: Any])] = []
        if body["buckets"] != nil {
            rows = (body["buckets"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["modelId"] as? String else { return nil }
                return (id, id, $0)
            }
        } else {
            rows = (body["models"] as? [String: [String: Any]] ?? [:]).compactMap { id, model in
                guard let quota = model["quotaInfo"] as? [String: Any] else { return nil }
                return (id, (model["displayName"] as? String) ?? (model["label"] as? String) ?? id, quota)
            }
        }
        var windows: [String: UsageWindow] = [:]
        for row in rows {
            guard !row.id.isEmpty, let fraction = row.quota["remainingFraction"] as? Double,
                  fraction.isFinite, (0...1).contains(fraction),
                  let reset = parseDate(row.quota["resetTime"] as? String) else { continue }
            let window = UsageWindow(
                utilization: (1 - fraction) * 100, resetsAt: reset,
                windowID: UsageWindowID(rawValue: "\(provider.rawValue).model.\(row.id)"),
                displayName: "\(row.label) limit", totalDuration: 0,
                scope: UsageWindowScope(model: row.id)
            )
            // Gemini may report input and output buckets for the same model.
            if let previous = windows[row.id], previous.utilization >= window.utilization { continue }
            windows[row.id] = window
        }
        guard !windows.isEmpty else { throw UsageError.invalidResponse }
        return ProviderUsageSnapshot(
            provider: provider, windows: windows.sorted { $0.key < $1.key }.map(\.value), planName: planName, fetchedAt: now
        )
    }
}
#endif
