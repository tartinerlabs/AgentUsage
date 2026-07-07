//
//  CursorUsageService.swift
//  ClaudeMeter
//
//  Cursor live usage from its dashboard backend.
//
//  Cursor writes no per-message token logs, so instead of the local-log token-cost
//  pipeline we read the access token Cursor's app stores locally (its `state.vscdb`
//  SQLite DB, with a keychain fallback) and call Cursor's dashboard endpoints for the
//  current billing cycle. `fetchSnapshot()` returns nil when Cursor isn't installed or
//  signed in, so the provider simply doesn't appear — mirroring Codex/OpenCode.
//
//  Auth token keys, endpoints, and response field names are factual details of Cursor's
//  (undocumented, volatile) backend; the approach here was derived from
//  robinebers/openusage (MIT). The mapper is intentionally defensive: every field is
//  optional and a shape it doesn't recognize degrades to nil rather than throwing.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog
import SQLite3

actor CursorUsageService {
    nonisolated let provider: Provider = .cursor

    enum CursorError: LocalizedError {
        /// The dashboard returned a 5xx status — treated as a service outage.
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .serverError(let code): return "Cursor dashboard server error (\(code))"
            }
        }
    }

    private let session: URLSession
    private let authLoader: @Sendable () -> CursorAuth?
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        authLoader: @escaping @Sendable () -> CursorAuth? = { CursorAuthLoader.load() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.authLoader = authLoader
        self.now = now
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let auth = authLoader(), var token = auth.accessToken?.trimmed, !token.isEmpty else {
            return nil
        }

        var (data, http) = try await postConnect(Constants.cursorUsageURL, token: token)

        // Access token likely rotates often; refresh once (in-memory only, no write-back
        // to Cursor's DB) and retry when the primary call is rejected.
        if (http.statusCode == 401 || http.statusCode == 403),
           let refreshed = try? await refreshAccessToken(auth.refreshToken) {
            token = refreshed
            (data, http) = try await postConnect(Constants.cursorUsageURL, token: token)
        }

        if (500...599).contains(http.statusCode) {
            Logger.tokenUsage.warning("Cursor usage endpoint returned \(http.statusCode)")
            throw CursorError.serverError(http.statusCode)
        }

        if http.statusCode == 200, let usage = Self.jsonObject(data) {
            let planName = await fetchPlanName(token: token)
            if let snapshot = Self.mapUsage(usage, planName: planName, now: now()) {
                return snapshot
            }
        }

        // Legacy request-quota accounts don't return `planUsage`; fall back to the REST usage API.
        return try await fetchRequestBased(token: token)
    }

    // MARK: - Networking

    private func postConnect(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: Constants.cursorConnectProtocolVersionHeader)
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorError.serverError(-1)
        }
        return (data, http)
    }

    /// Best-effort plan name from `GetPlanInfo` (`planInfo.planName`, e.g. "Free"/"Pro").
    /// A miss returns nil and must not hide otherwise-valid usage.
    private func fetchPlanName(token: String) async -> String? {
        guard let (data, http) = try? await postConnect(Constants.cursorPlanURL, token: token),
              http.statusCode == 200,
              let body = Self.jsonObject(data),
              let planInfo = body["planInfo"] as? [String: Any],
              let name = planInfo["planName"] as? String else {
            return nil
        }
        return Self.titleCased(name)
    }

    /// Refresh the access token in memory for this fetch only. We deliberately do NOT
    /// persist the rotated token back to Cursor's state DB / keychain to avoid racing or
    /// corrupting Cursor's own storage; the refreshed token is valid for this session.
    private func refreshAccessToken(_ refreshToken: String?) async throws -> String? {
        guard let refreshToken = refreshToken?.trimmed, !refreshToken.isEmpty else { return nil }
        var request = URLRequest(url: Constants.cursorTokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Constants.cursorOAuthClientID,
            "refresh_token": refreshToken
        ])
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = Self.jsonObject(data),
              let token = (body["access_token"] as? String)?.trimmed, !token.isEmpty else {
            return nil
        }
        return token
    }

    /// REST fallback for legacy premium-request accounts (`cursor.com/api/usage`).
    private func fetchRequestBased(token: String) async throws -> ProviderUsageSnapshot? {
        guard let userID = Self.jwtUserID(token) else { return nil }
        var components = URLComponents(url: Constants.cursorRestUsageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user", value: userID)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // WorkOS session cookie is `<userID>::<accessToken>`, URL-encoded.
        request.setValue("WorkosCursorSessionToken=\(userID)%3A%3A\(token)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if (500...599).contains(http.statusCode) { throw CursorError.serverError(http.statusCode) }
        guard http.statusCode == 200, let usage = Self.jsonObject(data) else { return nil }
        return Self.mapRequestBased(usage, planName: nil, now: now())
    }

    // MARK: - Mapping (pure, unit-testable)

    /// Map `GetCurrentPeriodUsage` JSON to a snapshot. Returns nil when the account has no
    /// active plan usage (caller then tries the request-based REST fallback).
    nonisolated static func mapUsage(_ usage: [String: Any], planName: String?, now: Date) -> ProviderUsageSnapshot? {
        guard usage["enabled"] as? Bool != false,
              let planUsage = usage["planUsage"] as? [String: Any] else {
            return nil
        }

        let limitCents = number(planUsage["limit"])
        let remainingCents = number(planUsage["remaining"])
        let usedCents = number(planUsage["totalSpend"])
            ?? ((limitCents ?? 0) - (remainingCents ?? 0))

        // Total-usage percent: prefer the API's own figure, else derive it from limit/spend.
        let totalPercent = number(planUsage["totalPercentUsed"])
            ?? limitCents.flatMap { $0 > 0 ? clamp(usedCents / $0 * 100) : nil }
        guard let totalPercent else { return nil }  // no usable plan-usage shape

        let resetsAt = billingCycleEnd(from: usage) ?? now.addingTimeInterval(30 * 24 * 60 * 60)

        var windows: [UsageWindow] = [
            UsageWindow(utilization: totalPercent, resetsAt: resetsAt, windowType: .cursorTotal)
        ]
        if let auto = number(planUsage["autoPercentUsed"]) {
            windows.append(UsageWindow(utilization: clamp(auto), resetsAt: resetsAt, windowType: .cursorAuto))
        }
        if let api = number(planUsage["apiPercentUsed"]) {
            windows.append(UsageWindow(utilization: clamp(api), resetsAt: resetsAt, windowType: .cursorApi))
        }

        let extraUsage = onDemandSpend(usage["spendLimitUsage"] as? [String: Any])

        return ProviderUsageSnapshot(
            provider: .cursor,
            windows: windows,
            extraUsage: extraUsage,
            planName: planName?.nonEmpty,
            fetchedAt: now
        )
    }

    /// Map the legacy `cursor.com/api/usage` request-quota response to a single Requests window.
    nonisolated static func mapRequestBased(_ usage: [String: Any], planName: String?, now: Date) -> ProviderUsageSnapshot? {
        guard let gpt4 = usage["gpt-4"] as? [String: Any],
              let limit = number(gpt4["maxRequestUsage"]), limit > 0 else {
            return nil
        }
        let used = number(gpt4["numRequests"]) ?? 0
        let cycleStart = (usage["startOfMonth"] as? String).flatMap(parseISO8601)
        let resetsAt = (cycleStart ?? now).addingTimeInterval(30 * 24 * 60 * 60)
        let window = UsageWindow(
            utilization: clamp(used / limit * 100),
            resetsAt: resetsAt,
            windowType: .cursorRequests
        )
        return ProviderUsageSnapshot(
            provider: .cursor,
            windows: [window],
            planName: planName?.nonEmpty,
            fetchedAt: now
        )
    }

    /// On-demand ("usage-based pricing") dollar spend against the spend limit.
    ///
    /// Field names track Cursor's live response: the effective figures are `overallLimit` /
    /// `overallRemaining`, with `individual*` / `pooled*` as fallbacks. No "used" field is
    /// exposed, so spend is derived as limit − remaining; an explicit `*Used` / `totalSpend`
    /// field (older shape) is preferred when present. Values are integer cents.
    private nonisolated static func onDemandSpend(_ spendLimitUsage: [String: Any]?) -> ExtraUsageCost? {
        guard let spendLimitUsage else { return nil }
        let limitCents = number(spendLimitUsage["overallLimit"])
            ?? number(spendLimitUsage["individualLimit"])
            ?? number(spendLimitUsage["pooledLimit"]) ?? 0
        guard limitCents > 0 else { return nil }
        let remainingCents = number(spendLimitUsage["overallRemaining"])
            ?? number(spendLimitUsage["individualRemaining"])
            ?? number(spendLimitUsage["pooledRemaining"]) ?? 0
        let spentCents = [
            number(spendLimitUsage["individualUsed"]),
            number(spendLimitUsage["pooledUsed"]),
            number(spendLimitUsage["totalSpend"])
        ].compactMap { $0 }.first { $0 > 0 } ?? max(0, limitCents - remainingCents)
        return ExtraUsageCost(used: spentCents / 100, limit: limitCents / 100, currencyCode: "USD")
    }

    // MARK: - Parsing helpers

    private nonisolated static func billingCycleEnd(from usage: [String: Any]) -> Date? {
        guard let endMs = number(usage["billingCycleEnd"]), endMs > 0 else { return nil }
        return Date(timeIntervalSince1970: endMs / 1000)
    }

    nonisolated static func jsonObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Permissive numeric read: JSON numbers or numeric strings, rejecting non-finite values.
    nonisolated static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = value as? String, let d = Double(s.trimmed) { return d.isFinite ? d : nil }
        return nil
    }

    private nonisolated static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private nonisolated static func titleCased(_ value: String) -> String {
        value.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private nonisolated static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// The Cursor userID used to build the WorkOS session cookie, from the JWT `sub`
    /// (`auth0|user_XXX` → `user_XXX`).
    nonisolated static func jwtUserID(_ token: String) -> String? {
        guard let payload = jwtPayload(token), let sub = payload["sub"] as? String else { return nil }
        let parts = sub.split(separator: "|", omittingEmptySubsequences: false)
        let userID = String(parts.count > 1 ? parts[1] : parts[0])
        return userID.isEmpty ? nil : userID
    }

    /// Decode a JWT payload (middle base64url segment) as a JSON object.
    nonisolated static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !payload.count.isMultiple(of: 4) { payload.append("=") }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Auth loading

struct CursorAuth: Sendable, Equatable {
    var accessToken: String?
    var refreshToken: String?
}

/// Reads Cursor's locally-stored auth tokens: the `state.vscdb` SQLite DB first, then the
/// `cursor-access-token` / `cursor-refresh-token` keychain entries as a fallback.
enum CursorAuthLoader {
    static func load(
        stateDBURLs: [URL] = Constants.cursorStateDBURLs,
        fileManager: FileManager = .default
    ) -> CursorAuth? {
        if let dbURL = stateDBURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            let access = readStateValue(dbURL: dbURL, key: Constants.cursorStateAccessTokenKey)
            let refresh = readStateValue(dbURL: dbURL, key: Constants.cursorStateRefreshTokenKey)
            if access != nil || refresh != nil {
                return CursorAuth(accessToken: access, refreshToken: refresh)
            }
        }

        let keychainAccess = readKeychain(service: Constants.cursorKeychainAccessTokenService)
        let keychainRefresh = readKeychain(service: Constants.cursorKeychainRefreshTokenService)
        if keychainAccess != nil || keychainRefresh != nil {
            return CursorAuth(accessToken: keychainAccess, refreshToken: keychainRefresh)
        }
        return nil
    }

    // MARK: SQLite

    private static func readStateValue(dbURL: URL, key: String) -> String? {
        var db: OpaquePointer?
        // Cursor keeps `state.vscdb` open in WAL mode while it runs, and a plain read-only
        // open then intermittently fails to acquire the shared-memory lock. `immutable=1`
        // tells SQLite the file won't change so it skips all locking/WAL and reads the base
        // file directly — safe here because the auth token changes rarely (a token written
        // only to the -wal since the last checkpoint is picked up on the next refresh).
        // Percent-encode the path (it contains spaces, e.g. "Application Support") so the
        // SQLite URI parser accepts it.
        let encodedPath = dbURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbURL.path
        let uri = "file:\(encodedPath)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_TRANSIENT: sqlite must copy the key bytes (the Swift String is transient).
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)

        guard sqlite3_step(stmt) == SQLITE_ROW, let valueC = sqlite3_column_text(stmt, 0) else { return nil }
        let value = String(cString: valueC).trimmed
        return value.isEmpty ? nil : value
    }

    // MARK: Keychain (via the Apple-signed `security` CLI, like MacOSCredentialService)

    private static func readKeychain(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = (String(data: data, encoding: .utf8) ?? "").trimmed
        return value.isEmpty ? nil : value
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : self }
}
#endif
