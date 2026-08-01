//
//  CursorUsageService.swift
//  AgentUsage
//
//  Cursor subscription usage from the signed-in dashboard session.
//

#if os(macOS)
import CoreFoundation
import Foundation
import AgentUsageKit
import OSLog
import SQLite3

nonisolated struct CursorAuth: Sendable, Equatable {
    enum Source: String, Sendable {
        case sqlite
        case keychain
    }

    var accessToken: String?
    var refreshToken: String?
    let source: Source
    let membershipType: String?
}

/// JWT helpers shared by auth-source selection and the dashboard cookie fallback.
nonisolated enum CursorToken {
    static func payload(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !encoded.count.isMultiple(of: 4) {
            encoded.append("=")
        }
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func subject(_ token: String?) -> String? {
        guard let subject = payload(token)?["sub"] as? String else { return nil }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func expiration(_ token: String?) -> Date? {
        guard let value = CursorUsageService.number(payload(token)?["exp"]) else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}

/// Read-only discovery of Cursor-owned credentials.
///
/// Cursor keeps `state.vscdb` open in WAL mode. `immutable=1` avoids taking a
/// lock while still ensuring AgentUsage never writes to Cursor's database.
nonisolated struct CursorAuthLoader: Sendable {
    typealias KeychainReader = @Sendable (String) -> String?

    private let stateDBURLs: [URL]
    private let keychainReader: KeychainReader

    init(
        stateDBURLs: [URL] = Constants.cursorStateDBURLs,
        keychainReader: @escaping KeychainReader = {
            CursorAuthLoader.readKeychainValue(service: $0)
        }
    ) {
        self.stateDBURLs = stateDBURLs
        self.keychainReader = keychainReader
    }

    func loadCandidates() -> [CursorAuth] {
        let sqlite = loadSQLiteCandidate()
        let keychain = loadKeychainCandidate()

        guard let sqlite else {
            return keychain.map { [$0] } ?? []
        }
        guard let keychain else {
            return [sqlite]
        }

        if sqlite.accessToken == keychain.accessToken,
           sqlite.refreshToken == keychain.refreshToken {
            return [sqlite]
        }

        let sqliteSubject = CursorToken.subject(sqlite.accessToken)
        let keychainSubject = CursorToken.subject(keychain.accessToken)
        let subjectsDiffer = sqliteSubject != nil
            && keychainSubject != nil
            && sqliteSubject != keychainSubject
        if sqlite.membershipType == "free", subjectsDiffer {
            return [keychain, sqlite]
        }
        return [sqlite, keychain]
    }

    func loadSQLiteCandidate() -> CursorAuth? {
        let fileManager = FileManager.default
        for url in stateDBURLs where fileManager.fileExists(atPath: url.path) {
            guard let values = Self.readStateValues(at: url),
                  values.accessToken != nil || values.refreshToken != nil else {
                continue
            }
            return CursorAuth(
                accessToken: values.accessToken,
                refreshToken: values.refreshToken,
                source: .sqlite,
                membershipType: values.membershipType
            )
        }
        return nil
    }

    func loadKeychainCandidate() -> CursorAuth? {
        let access = keychainReader(Constants.cursorKeychainAccessTokenService)?.trimmed.nonEmpty
        let refresh = keychainReader(Constants.cursorKeychainRefreshTokenService)?.trimmed.nonEmpty
        guard access != nil || refresh != nil else { return nil }
        return CursorAuth(
            accessToken: access,
            refreshToken: refresh,
            source: .keychain,
            membershipType: nil
        )
    }

    struct StateValues: Sendable, Equatable {
        let accessToken: String?
        let refreshToken: String?
        let membershipType: String?
    }

    static func readStateValues(at url: URL) -> StateValues? {
        var database: OpaquePointer?
        let encodedPath = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? url.path
        let uri = "file:\(encodedPath)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)

        let access = readValue(
            key: Constants.cursorStateAccessTokenKey,
            database: database
        )
        let refresh = readValue(
            key: Constants.cursorStateRefreshTokenKey,
            database: database
        )
        let membership = readValue(
            key: Constants.cursorStateMembershipTypeKey,
            database: database
        )?.lowercased()
        return StateValues(
            accessToken: access,
            refreshToken: refresh,
            membershipType: membership
        )
    }

    private static func readValue(key: String, database: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value).trimmed.nonEmpty
    }

    private static func readKeychainValue(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmed.nonEmpty
    }
}

/// Fetches Cursor's live billing-cycle quota from its signed-in dashboard APIs.
///
/// Cursor's documented Admin APIs are team/Enterprise-only. This service reads
/// the local Cursor session and uses the same personal dashboard endpoints as
/// Cursor itself. The response mapper is intentionally defensive because these
/// endpoints are undocumented and vary by account type. The approach is based
/// on OpenUsage's Cursor provider (MIT), adapted to AgentUsage's data model.
actor CursorUsageService: ProviderUsageServiceProtocol {
    nonisolated let provider: Provider = .cursor

    enum CursorError: LocalizedError {
        case unauthorized
        case networkError(Error)
        case invalidResponse
        case rateLimited
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Cursor session expired. Sign in again in Cursor."
            case .networkError(let error):
                "Cursor usage network error: \(error.localizedDescription)"
            case .invalidResponse:
                "Cursor returned an invalid usage response."
            case .rateLimited:
                "Cursor usage is temporarily rate limited."
            case .serverError(let code):
                "Cursor usage service error: \(code)"
            }
        }
    }

    struct BillingCycle: Sendable, Equatable {
        let resetsAt: Date
        let duration: TimeInterval
    }

    struct CookieSession: Sendable, Equatable {
        let userID: String
        let cookieValue: String
    }

    private struct OptionalRESTResponse: Sendable {
        let data: Data?
        let serverErrorCode: Int?
    }

    private let session: URLSession
    private let authLoader: @Sendable () -> [CursorAuth]
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var sessionAuth: CursorAuth?

    init(
        session: URLSession = .shared,
        authLoader: @escaping @Sendable () -> [CursorAuth] = {
            CursorAuthLoader().loadCandidates()
        },
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.session = session
        self.authLoader = authLoader
        self.now = now
        self.calendar = calendar
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        let storedCandidates = authLoader()
        let candidates = candidates(storedCandidates: storedCandidates)
        guard !candidates.isEmpty else {
            Logger.cursor.info("No Cursor credentials found; skipping live usage fetch")
            sessionAuth = nil
            return nil
        }

        for candidate in candidates {
            do {
                let result = try await fetchSnapshot(using: candidate)
                if let snapshot = result.snapshot {
                    sessionAuth = result.auth
                    return snapshot
                }
            } catch let error as CursorError {
                if case .unauthorized = error {
                    if sessionAuth?.source == candidate.source {
                        sessionAuth = nil
                    }
                    continue
                }
                throw error
            }
        }

        sessionAuth = nil
        return nil
    }

    private func candidates(storedCandidates: [CursorAuth]) -> [CursorAuth] {
        guard let sessionAuth,
              storedCandidates.contains(where: { Self.sameIdentity(sessionAuth, $0) }) else {
            return storedCandidates
        }
        return [sessionAuth] + storedCandidates.filter { !Self.sameCredential(sessionAuth, $0) }
    }

    private static func sameIdentity(_ lhs: CursorAuth, _ rhs: CursorAuth) -> Bool {
        guard lhs.source == rhs.source else { return false }
        if let lhsSubject = CursorToken.subject(lhs.accessToken),
           let rhsSubject = CursorToken.subject(rhs.accessToken) {
            return lhsSubject == rhsSubject
        }
        if let lhsRefresh = lhs.refreshToken, let rhsRefresh = rhs.refreshToken {
            return lhsRefresh == rhsRefresh
        }
        return lhs.accessToken == rhs.accessToken
    }

    private static func sameCredential(_ lhs: CursorAuth, _ rhs: CursorAuth) -> Bool {
        lhs.source == rhs.source
            && lhs.accessToken == rhs.accessToken
            && lhs.refreshToken == rhs.refreshToken
    }

    private func fetchSnapshot(
        using initialAuth: CursorAuth
    ) async throws -> (snapshot: ProviderUsageSnapshot?, auth: CursorAuth) {
        var auth = try await preparedAuth(initialAuth)
        guard var accessToken = auth.accessToken?.trimmed.nonEmpty else {
            throw CursorError.unauthorized
        }

        var response = try await connectPost(
            url: Constants.cursorUsageURL,
            accessToken: accessToken
        )
        if response.http.statusCode == 401 || response.http.statusCode == 403 {
            guard let refreshed = try await refreshedAuth(auth) else {
                throw CursorError.unauthorized
            }
            auth = refreshed
            guard let refreshedAccess = auth.accessToken?.trimmed.nonEmpty else {
                throw CursorError.unauthorized
            }
            accessToken = refreshedAccess
            response = try await connectPost(
                url: Constants.cursorUsageURL,
                accessToken: accessToken
            )
        }

        try Self.requireNonTransientStatus(response.http.statusCode)
        guard (200..<300).contains(response.http.statusCode) else {
            let fallback = try await fetchFallbackSnapshot(
                accessToken: accessToken,
                planName: nil
            )
            return (fallback, auth)
        }

        let usage = Self.jsonObject(response.data)
        let planName = await fetchPlanName(accessToken: accessToken)
        if let usage,
           let snapshot = Self.mapPrimaryUsage(
               usage,
               planName: planName,
               now: now()
           ) {
            return (snapshot, auth)
        }

        let fallback = try await fetchFallbackSnapshot(
            accessToken: accessToken,
            planName: planName
        )
        return (fallback, auth)
    }

    private func preparedAuth(_ initialAuth: CursorAuth) async throws -> CursorAuth {
        guard Self.needsRefresh(initialAuth.accessToken, now: now()) else {
            return initialAuth
        }
        do {
            if let refreshed = try await refreshedAuth(initialAuth) {
                return refreshed
            }
        } catch {
            if Self.isExpired(initialAuth.accessToken, now: now()) {
                throw error
            }
        }
        guard !Self.isExpired(initialAuth.accessToken, now: now()),
              initialAuth.accessToken?.trimmed.nonEmpty != nil else {
            throw CursorError.unauthorized
        }
        return initialAuth
    }

    private func refreshedAuth(_ auth: CursorAuth) async throws -> CursorAuth? {
        guard let refreshToken = auth.refreshToken?.trimmed.nonEmpty else {
            return nil
        }
        var request = URLRequest(url: Constants.cursorTokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Constants.cursorOAuthClientID,
            "refresh_token": refreshToken,
        ])
        request.timeoutInterval = 15

        let response = try await perform(request)
        try Self.requireNonTransientStatus(response.http.statusCode)
        guard (200..<300).contains(response.http.statusCode),
              let body = Self.jsonObject(response.data),
              body["shouldLogout"] as? Bool != true,
              let accessToken = (body["access_token"] as? String)?.trimmed.nonEmpty else {
            return nil
        }
        let rotatedRefresh = (body["refresh_token"] as? String)?.trimmed.nonEmpty
            ?? auth.refreshToken
        guard let currentSubject = CursorToken.subject(auth.accessToken),
              CursorToken.subject(accessToken) == currentSubject else {
            return nil
        }
        return CursorAuth(
            accessToken: accessToken,
            refreshToken: rotatedRefresh,
            source: auth.source,
            membershipType: auth.membershipType
        )
    }

    private func fetchPlanName(accessToken: String) async -> String? {
        do {
            let response = try await connectPost(
                url: Constants.cursorPlanURL,
                accessToken: accessToken
            )
            guard (200..<300).contains(response.http.statusCode),
                  let body = Self.jsonObject(response.data),
                  let planInfo = body["planInfo"] as? [String: Any],
                  let name = (planInfo["planName"] as? String)?.trimmed.nonEmpty else {
                return nil
            }
            return Self.planLabel(name)
        } catch {
            Logger.cursor.info("Optional Cursor plan fetch failed")
            return nil
        }
    }

    private func fetchFallbackSnapshot(
        accessToken: String,
        planName: String?
    ) async throws -> ProviderUsageSnapshot? {
        guard let cookieSession = Self.cookieSession(accessToken: accessToken) else {
            return nil
        }

        async let summary = fetchOptionalRESTJSON(
            url: Constants.cursorUsageSummaryURL,
            cookieSession: cookieSession
        )

        var components = URLComponents(
            url: Constants.cursorLegacyUsageURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "user", value: cookieSession.userID),
        ]
        let legacyURL = components?.url
        async let legacy = fetchOptionalRESTJSON(
            url: legacyURL,
            cookieSession: cookieSession
        )

        let responses = await (summary, legacy)
        if let snapshot = Self.mapFallbackUsage(
            summary: responses.0.data.flatMap(Self.jsonObject),
            legacy: responses.1.data.flatMap(Self.jsonObject),
            planName: planName,
            now: now(),
            calendar: calendar
        ) {
            return snapshot
        }
        if let code = responses.0.serverErrorCode ?? responses.1.serverErrorCode {
            // A fallback is only authoritative when no usable primary/fallback
            // snapshot exists. Preserve cached data and surface the outage then.
            throw CursorError.serverError(code)
        }
        return nil
    }

    private func fetchOptionalRESTJSON(
        url: URL?,
        cookieSession: CookieSession
    ) async -> OptionalRESTResponse {
        guard let url else {
            return OptionalRESTResponse(data: nil, serverErrorCode: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "WorkosCursorSessionToken=\(cookieSession.cookieValue)",
            forHTTPHeaderField: "Cookie"
        )
        request.timeoutInterval = 10

        do {
            let response = try await perform(request)
            if (500...599).contains(response.http.statusCode) {
                return OptionalRESTResponse(
                    data: nil,
                    serverErrorCode: response.http.statusCode
                )
            }
            guard (200..<300).contains(response.http.statusCode) else {
                return OptionalRESTResponse(data: nil, serverErrorCode: nil)
            }
            return OptionalRESTResponse(
                data: response.data,
                serverErrorCode: nil
            )
        } catch {
            Logger.cursor.info("Optional Cursor dashboard fallback failed")
            return OptionalRESTResponse(data: nil, serverErrorCode: nil)
        }
    }

    private func connectPost(
        url: URL,
        accessToken: String
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: Constants.cursorConnectProtocolVersionHeader)
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15
        return try await perform(request)
    }

    private func perform(
        _ request: URLRequest
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CursorError.invalidResponse
            }
            return (data, http)
        } catch let error as CursorError {
            throw error
        } catch {
            throw CursorError.networkError(error)
        }
    }

    private static func requireNonTransientStatus(_ statusCode: Int) throws {
        if statusCode == 429 {
            throw CursorError.rateLimited
        }
        if (500...599).contains(statusCode) {
            throw CursorError.serverError(statusCode)
        }
    }

    // MARK: - Mapping

    nonisolated static func mapPrimaryUsage(
        _ usage: [String: Any],
        planName: String?,
        now: Date
    ) -> ProviderUsageSnapshot? {
        guard usage["enabled"] as? Bool != false,
              let planUsage = usage["planUsage"] as? [String: Any],
              let cycle = primaryBillingCycle(usage, now: now) else {
            return nil
        }

        var windows: [UsageWindow] = []
        if let total = primaryTotalPercent(planUsage) {
            windows.append(window(
                utilization: total,
                id: "cursor.total",
                displayName: "Total usage",
                cycle: cycle
            ))
        }
        if let auto = number(planUsage["autoPercentUsed"]) {
            windows.append(window(
                utilization: auto,
                id: "cursor.auto",
                displayName: "Auto usage",
                cycle: cycle
            ))
        }
        if let api = number(planUsage["apiPercentUsed"]) {
            windows.append(window(
                utilization: api,
                id: "cursor.api",
                displayName: "API usage",
                cycle: cycle
            ))
        }
        guard !windows.isEmpty else { return nil }

        return ProviderUsageSnapshot(
            provider: .cursor,
            windows: windows,
            extraUsage: mapPrimaryOnDemand(
                usage["spendLimitUsage"] as? [String: Any]
            ),
            planName: planLabel(planName),
            fetchedAt: now
        )
    }

    nonisolated static func mapFallbackUsage(
        summary: [String: Any]?,
        legacy: [String: Any]?,
        planName: String?,
        now: Date,
        calendar: Calendar
    ) -> ProviderUsageSnapshot? {
        guard let cycle = fallbackBillingCycle(
            summary: summary,
            legacy: legacy,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }

        var windows: [UsageWindow] = []
        let requestUsage = legacy?["gpt-4"] as? [String: Any]
        if let limit = number(requestUsage?["maxRequestUsage"]), limit > 0,
           let used = number(requestUsage?["numRequests"])
            ?? number(requestUsage?["numRequestsTotal"]) {
            windows.append(window(
                utilization: used / limit * 100,
                id: "cursor.requests",
                displayName: "Requests",
                cycle: cycle
            ))
        } else if let total = summaryTotalPercent(summary) {
            windows.append(window(
                utilization: total,
                id: "cursor.total",
                displayName: "Total usage",
                cycle: cycle
            ))
        }

        let plan = ((summary?["individualUsage"] as? [String: Any])?["plan"]
            as? [String: Any])
        if let auto = number(plan?["autoPercentUsed"]) {
            windows.append(window(
                utilization: auto,
                id: "cursor.auto",
                displayName: "Auto usage",
                cycle: cycle
            ))
        }
        if let api = number(plan?["apiPercentUsed"]) {
            windows.append(window(
                utilization: api,
                id: "cursor.api",
                displayName: "API usage",
                cycle: cycle
            ))
        }
        guard !windows.isEmpty else { return nil }

        let membership = planName ?? (summary?["membershipType"] as? String)
        return ProviderUsageSnapshot(
            provider: .cursor,
            windows: windows,
            extraUsage: mapSummaryOnDemand(summary),
            planName: planLabel(membership),
            fetchedAt: now
        )
    }

    private nonisolated static func primaryTotalPercent(
        _ planUsage: [String: Any]
    ) -> Double? {
        if let explicit = number(planUsage["totalPercentUsed"]) {
            return clampedPercent(explicit)
        }
        guard let limit = number(planUsage["limit"]), limit > 0 else {
            return nil
        }
        let used: Double?
        if let totalSpend = number(planUsage["totalSpend"]), totalSpend >= 0 {
            used = totalSpend
        } else if let remaining = number(planUsage["remaining"]), remaining >= 0 {
            used = max(0, limit - remaining)
        } else {
            used = nil
        }
        return used.map { clampedPercent($0 / limit * 100) }
    }

    private nonisolated static func summaryTotalPercent(
        _ summary: [String: Any]?
    ) -> Double? {
        let individual = summary?["individualUsage"] as? [String: Any]
        let team = summary?["teamUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        if let explicit = number(plan?["totalPercentUsed"]) {
            return clampedPercent(explicit)
        }

        let limitType = (summary?["limitType"] as? String)?.lowercased()
        let bucket: [String: Any]?
        if limitType == "team" {
            bucket = team?["pooled"] as? [String: Any]
        } else {
            bucket = (individual?["overall"] as? [String: Any])
                ?? (team?["pooled"] as? [String: Any])
        }
        guard let meter = coherentMeter(
            bucket,
            limitKey: "limit",
            usedKey: "used",
            remainingKey: "remaining"
        ) else {
            return nil
        }
        return clampedPercent(meter.used / meter.limit * 100)
    }

    private nonisolated static func mapPrimaryOnDemand(
        _ usage: [String: Any]?
    ) -> ExtraUsageCost? {
        guard let usage else { return nil }

        let limitType = (usage["limitType"] as? String)?.lowercased()
        var scopes = ["overall"]
        if limitType == "team" || limitType == "pooled" {
            scopes.append(contentsOf: ["pooled", "individual"])
        } else {
            scopes.append(contentsOf: ["individual", "pooled"])
        }

        for scope in scopes {
            guard let meter = coherentMeter(
                usage,
                limitKey: "\(scope)Limit",
                usedKey: "\(scope)Used",
                remainingKey: "\(scope)Remaining"
            ) else {
                continue
            }
            return ExtraUsageCost(
                used: meter.used / 100,
                limit: meter.limit / 100,
                currencyCode: "USD"
            )
        }
        return nil
    }

    private nonisolated static func mapSummaryOnDemand(
        _ summary: [String: Any]?
    ) -> ExtraUsageCost? {
        let individual = summary?["individualUsage"] as? [String: Any]
        let team = summary?["teamUsage"] as? [String: Any]
        for bucket in [individual?["onDemand"], team?["onDemand"]] {
            guard let meter = coherentMeter(
                bucket as? [String: Any],
                limitKey: "limit",
                usedKey: "used",
                remainingKey: "remaining"
            ) else {
                continue
            }
            return ExtraUsageCost(
                used: meter.used / 100,
                limit: meter.limit / 100,
                currencyCode: "USD"
            )
        }
        return nil
    }

    private nonisolated static func coherentMeter(
        _ object: [String: Any]?,
        limitKey: String,
        usedKey: String,
        remainingKey: String
    ) -> (used: Double, limit: Double)? {
        guard let object,
              object["enabled"] as? Bool != false,
              let limit = number(object[limitKey]),
              limit > 0 else {
            return nil
        }
        if let used = number(object[usedKey]), used >= 0 {
            return (used, limit)
        }
        guard let remaining = number(object[remainingKey]), remaining >= 0 else {
            return nil
        }
        return (max(0, limit - remaining), limit)
    }

    private nonisolated static func primaryBillingCycle(
        _ usage: [String: Any],
        now: Date
    ) -> BillingCycle? {
        let start: Date?
        let end: Date?
        if let startMilliseconds = number(usage["billingCycleStart"]),
           let endMilliseconds = number(usage["billingCycleEnd"]) {
            start = Date(timeIntervalSince1970: startMilliseconds / 1_000)
            end = Date(timeIntervalSince1970: endMilliseconds / 1_000)
        } else if let startValue = usage["billingCycleStart"] as? String,
                  let endValue = usage["billingCycleEnd"] as? String {
            start = parseISO8601(startValue)
            end = parseISO8601(endValue)
        } else {
            start = nil
            end = nil
        }

        guard let start, let end, end > start, end > now else { return nil }
        return BillingCycle(
            resetsAt: end,
            duration: end.timeIntervalSince(start)
        )
    }

    private nonisolated static func fallbackBillingCycle(
        summary: [String: Any]?,
        legacy: [String: Any]?,
        now: Date,
        calendar: Calendar
    ) -> BillingCycle? {
        if let startValue = summary?["billingCycleStart"] as? String,
           let endValue = summary?["billingCycleEnd"] as? String,
           let start = parseISO8601(startValue),
           let end = parseISO8601(endValue),
           end > start,
           end > now {
            return BillingCycle(
                resetsAt: end,
                duration: end.timeIntervalSince(start)
            )
        }

        guard let startValue = legacy?["startOfMonth"] as? String,
              let start = parseISO8601(startValue),
              let end = calendar.date(byAdding: .month, value: 1, to: start),
              end > start,
              end > now else {
            return nil
        }
        return BillingCycle(
            resetsAt: end,
            duration: end.timeIntervalSince(start)
        )
    }

    private nonisolated static func window(
        utilization: Double,
        id: UsageWindowID,
        displayName: String,
        cycle: BillingCycle
    ) -> UsageWindow {
        UsageWindow(
            utilization: clampedPercent(utilization),
            resetsAt: cycle.resetsAt,
            windowID: id,
            displayName: displayName,
            totalDuration: cycle.duration
        )
    }

    nonisolated static func cookieSession(accessToken: String) -> CookieSession? {
        guard let subject = CursorToken.subject(accessToken) else { return nil }
        let components = subject.split(separator: "|", omittingEmptySubsequences: false)
        let userID = String(components.count > 1 ? components[1] : components[0])
        guard !userID.isEmpty else { return nil }
        return CookieSession(
            userID: userID,
            cookieValue: "\(userID)%3A%3A\(accessToken)"
        )
    }

    nonisolated static func needsRefresh(
        _ accessToken: String?,
        now: Date,
        buffer: TimeInterval = 5 * 60
    ) -> Bool {
        guard let expiration = CursorToken.expiration(accessToken) else {
            return true
        }
        return expiration.timeIntervalSince(now) <= buffer
    }

    nonisolated static func isExpired(_ accessToken: String?, now: Date) -> Bool {
        guard let expiration = CursorToken.expiration(accessToken) else {
            return accessToken?.trimmed.nonEmpty == nil
        }
        return expiration <= now
    }

    nonisolated static func jsonObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        if let value = value as? String,
           let number = Double(value.trimmed),
           number.isFinite {
            return number
        }
        return nil
    }

    private nonisolated static func clampedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private nonisolated static func planLabel(_ value: String?) -> String? {
        guard let value = value?.trimmed.nonEmpty else { return nil }
        return value.split(whereSeparator: \.isWhitespace)
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private nonisolated static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private nonisolated extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
