//
//  CursorUsageServiceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("Cursor Usage Service", .serialized)
struct CursorUsageServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func mapsPrimaryPercentagesExactCycleAndSpend() throws {
        let start = now.addingTimeInterval(-12 * 24 * 3_600)
        let end = now.addingTimeInterval(19 * 24 * 3_600)
        let usage: [String: Any] = [
            "enabled": true,
            "billingCycleStart": start.timeIntervalSince1970 * 1_000,
            "billingCycleEnd": end.timeIntervalSince1970 * 1_000,
            "planUsage": [
                "totalPercentUsed": 42.5,
                "autoPercentUsed": 30,
                "apiPercentUsed": 12.5,
            ],
            "spendLimitUsage": [
                "limitType": "user",
                "overallLimit": 5_000,
                "overallRemaining": 3_800,
            ],
        ]

        let snapshot = try #require(
            CursorUsageService.mapPrimaryUsage(usage, planName: "pro plus", now: now)
        )

        #expect(snapshot.provider == .cursor)
        #expect(snapshot.planName == "Pro Plus")
        #expect(snapshot.windows.map(\.windowID.rawValue) == [
            "cursor.total",
            "cursor.auto",
            "cursor.api",
        ])
        #expect(snapshot.windows.map(\.windowType) == [.custom, .custom, .custom])
        #expect(snapshot.windows.map(\.utilization) == [42.5, 30, 12.5])
        #expect(snapshot.windows.allSatisfy { $0.resetsAt == end })
        #expect(snapshot.windows.allSatisfy {
            $0.totalDuration == end.timeIntervalSince(start)
        })
        #expect(snapshot.extraUsage?.used == 12)
        #expect(snapshot.extraUsage?.limit == 50)
        #expect(snapshot.extraUsage?.currencyCode == "USD")
    }

    @Test func mapsPrimaryISO8601BillingCycle() throws {
        let usage: [String: Any] = [
            "billingCycleStart": "2027-01-01T00:00:00Z",
            "billingCycleEnd": "2027-02-01T00:00:00Z",
            "planUsage": ["totalPercentUsed": 18.75],
        ]

        let snapshot = try #require(
            CursorUsageService.mapPrimaryUsage(usage, planName: nil, now: now)
        )
        let reset = try #require(Self.iso8601("2027-02-01T00:00:00Z"))
        #expect(snapshot.windows.first?.resetsAt == reset)
        let duration = try #require(snapshot.windows.first?.totalDuration)
        #expect(abs(duration - 31 * 24 * 3_600) < 0.001)
    }

    @Test func preservesExplicitZeroFromJSONWithoutTreatingBooleanAsNumber() throws {
        let data = Data("""
        {
          "billingCycleStart": "2027-01-01T00:00:00Z",
          "billingCycleEnd": "2027-02-01T00:00:00Z",
          "planUsage": {
            "totalPercentUsed": 0,
            "autoPercentUsed": false
          }
        }
        """.utf8)
        let usage = try #require(CursorUsageService.jsonObject(data))

        let snapshot = try #require(
            CursorUsageService.mapPrimaryUsage(usage, planName: nil, now: now)
        )
        #expect(snapshot.windows.map(\.windowID.rawValue) == ["cursor.total"])
        #expect(snapshot.windows.first?.utilization == 0)
    }

    @Test func totalRequiresExplicitPercentOrMatchingSpendFields() {
        let base: [String: Any] = [
            "billingCycleStart": (now.timeIntervalSince1970 - 1_000) * 1_000,
            "billingCycleEnd": (now.timeIntervalSince1970 + 1_000) * 1_000,
        ]

        var limitOnly = base
        limitOnly["planUsage"] = ["limit": 4_000]
        #expect(CursorUsageService.mapPrimaryUsage(limitOnly, planName: nil, now: now) == nil)

        var fromSpend = base
        fromSpend["planUsage"] = ["limit": 4_000, "totalSpend": 1_000]
        #expect(
            CursorUsageService.mapPrimaryUsage(fromSpend, planName: nil, now: now)?
                .windows.first?.utilization == 25
        )

        var fromRemaining = base
        fromRemaining["planUsage"] = ["limit": 4_000, "remaining": 1_000]
        #expect(
            CursorUsageService.mapPrimaryUsage(fromRemaining, planName: nil, now: now)?
                .windows.first?.utilization == 75
        )
    }

    @Test func onDemandNeverMixesSpendScopes() throws {
        let usage: [String: Any] = [
            "billingCycleStart": (now.timeIntervalSince1970 - 1_000) * 1_000,
            "billingCycleEnd": (now.timeIntervalSince1970 + 1_000) * 1_000,
            "planUsage": ["totalPercentUsed": 10],
            "spendLimitUsage": [
                "limitType": "user",
                "overallLimit": 5_000,
                "overallRemaining": 2_000,
                // This must not be combined with overallLimit.
                "individualUsed": 1_200,
            ],
        ]

        let snapshot = try #require(
            CursorUsageService.mapPrimaryUsage(usage, planName: nil, now: now)
        )
        #expect(snapshot.extraUsage?.limit == 50)
        #expect(snapshot.extraUsage?.used == 30)
    }

    @Test func invalidOrIncompletePrimaryDataProducesNoSnapshot() {
        let malformed: [String: Any] = [
            "billingCycleStart": "not-a-number",
            "billingCycleEnd": "also-not-a-number",
            "planUsage": ["totalPercentUsed": "bad"],
        ]
        #expect(CursorUsageService.mapPrimaryUsage(malformed, planName: nil, now: now) == nil)

        let missingCycle: [String: Any] = [
            "planUsage": ["totalPercentUsed": 0],
        ]
        #expect(CursorUsageService.mapPrimaryUsage(missingCycle, planName: nil, now: now) == nil)
    }

    @Test func mapsEnterpriseSummaryAndRequestQuota() throws {
        let summary: [String: Any] = [
            "billingCycleStart": "2027-01-01T00:00:00.000Z",
            "billingCycleEnd": "2027-02-01T00:00:00.000Z",
            "membershipType": "enterprise",
            "limitType": "team",
            "individualUsage": [
                "plan": [
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 6.25,
                    "totalPercentUsed": 6.25,
                ],
                "onDemand": [
                    "enabled": true,
                    "used": 0,
                    "limit": 25_000,
                    "remaining": 25_000,
                ],
            ],
            "teamUsage": [
                "onDemand": [
                    "enabled": true,
                    "used": 75_000,
                    "limit": 600_000,
                    "remaining": 525_000,
                ],
            ],
        ]
        let legacy: [String: Any] = [
            "gpt-4": [
                "numRequests": 37,
                "numRequestsTotal": 37,
                "maxRequestUsage": 750,
            ],
            "startOfMonth": "2027-01-01T00:00:00.000Z",
        ]

        let snapshot = try #require(CursorUsageService.mapFallbackUsage(
            summary: summary,
            legacy: legacy,
            planName: nil,
            now: now,
            calendar: Self.utcCalendar
        ))

        #expect(snapshot.planName == "Enterprise")
        #expect(snapshot.windows.map(\.windowID.rawValue) == [
            "cursor.requests",
            "cursor.auto",
            "cursor.api",
        ])
        #expect(snapshot.windows.map(\.utilization) == [37.0 / 750.0 * 100, 0, 6.25])
        #expect(snapshot.windows.allSatisfy { $0.totalDuration == 31 * 24 * 3_600 })
        #expect(snapshot.extraUsage?.used == 0)
        #expect(snapshot.extraUsage?.limit == 250)
    }

    @Test func mapsPooledTeamSummaryWithoutRequestQuota() throws {
        let summary: [String: Any] = [
            "billingCycleStart": "2027-01-01T00:00:00Z",
            "billingCycleEnd": "2027-02-01T00:00:00Z",
            "membershipType": "team",
            "limitType": "team",
            "teamUsage": [
                "pooled": [
                    "enabled": true,
                    "used": 125_000,
                    "limit": 4_000_000,
                    "remaining": 3_875_000,
                ],
                "onDemand": [
                    "enabled": true,
                    "used": 50_000,
                    "limit": 500_000,
                ],
            ],
        ]

        let snapshot = try #require(CursorUsageService.mapFallbackUsage(
            summary: summary,
            legacy: nil,
            planName: nil,
            now: now,
            calendar: Self.utcCalendar
        ))
        #expect(snapshot.windows.first?.windowID.rawValue == "cursor.total")
        #expect(snapshot.windows.first?.utilization == 3.125)
        #expect(snapshot.extraUsage?.used == 500)
        #expect(snapshot.extraUsage?.limit == 5_000)
    }

    @Test func legacyResetAddsCalendarMonthInsteadOfThirtyDays() throws {
        let legacy: [String: Any] = [
            "gpt-4": ["numRequests": 25, "maxRequestUsage": 100],
            "startOfMonth": "2027-02-01T00:00:00Z",
        ]
        let februaryNow = try #require(Self.iso8601("2027-02-15T00:00:00Z"))

        let snapshot = try #require(CursorUsageService.mapFallbackUsage(
            summary: nil,
            legacy: legacy,
            planName: nil,
            now: februaryNow,
            calendar: Self.utcCalendar
        ))
        let reset = try #require(Self.iso8601("2027-03-01T00:00:00Z"))

        #expect(snapshot.windows.first?.resetsAt == reset)
        #expect(abs((snapshot.windows.first?.totalDuration ?? 0) - 28 * 24 * 3_600) < 0.001)
        #expect(snapshot.windows.first?.windowID.rawValue == "cursor.requests")
    }

    @Test func authLoaderReadsSQLiteImmutablyAndKeepsBothSources() throws {
        let sqliteAccess = Self.jwt(subject: "auth0|sqlite", expiration: now.addingTimeInterval(3_600))
        let keychainAccess = Self.jwt(subject: "auth0|keychain", expiration: now.addingTimeInterval(3_600))
        let database = try Self.writeStateDatabase(values: [
            Constants.cursorStateAccessTokenKey: sqliteAccess,
            Constants.cursorStateRefreshTokenKey: "sqlite-refresh",
            Constants.cursorStateMembershipTypeKey: "pro",
        ])
        let before = try FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as? Date
        let loader = CursorAuthLoader(
            stateDBURLs: [database],
            keychainReader: { service in
                switch service {
                case Constants.cursorKeychainAccessTokenService: keychainAccess
                case Constants.cursorKeychainRefreshTokenService: "keychain-refresh"
                default: nil
                }
            }
        )

        let candidates = loader.loadCandidates()
        let after = try FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as? Date

        #expect(candidates.map(\.source) == [.sqlite, .keychain])
        #expect(candidates[0].accessToken == sqliteAccess)
        #expect(candidates[1].accessToken == keychainAccess)
        #expect(before == after)
    }

    @Test func freeSQLiteAccountPrefersDifferentSubjectKeychainSession() throws {
        let sqliteAccess = Self.jwt(subject: "auth0|free-user", expiration: now.addingTimeInterval(3_600))
        let keychainAccess = Self.jwt(subject: "auth0|paid-user", expiration: now.addingTimeInterval(3_600))
        let database = try Self.writeStateDatabase(values: [
            Constants.cursorStateAccessTokenKey: sqliteAccess,
            Constants.cursorStateMembershipTypeKey: "free",
        ])
        let loader = CursorAuthLoader(
            stateDBURLs: [database],
            keychainReader: { service in
                service == Constants.cursorKeychainAccessTokenService ? keychainAccess : nil
            }
        )

        let candidates = loader.loadCandidates()

        #expect(candidates.map(\.source) == [.keychain, .sqlite])
        #expect(candidates.first?.accessToken == keychainAccess)
    }

    @Test func missingCredentialsReturnsNilWithoutNetwork() async throws {
        let recorder = RequestRecorder()
        let service = CursorUsageService(
            session: Self.mockSession { request in
                recorder.record(request)
                return Self.response(request, status: 500)
            },
            authLoader: { [] },
            now: { now },
            calendar: Self.utcCalendar
        )

        #expect(try await service.fetchSnapshot() == nil)
        #expect(recorder.requests.isEmpty)
    }

    @Test func staleSQLiteCredentialFallsBackToKeychain() async throws {
        let stale = Self.jwt(subject: "auth0|stale", expiration: now.addingTimeInterval(3_600))
        let valid = Self.jwt(subject: "auth0|valid", expiration: now.addingTimeInterval(3_600))
        let recorder = RequestRecorder()
        let service = CursorUsageService(
            session: Self.mockSession { request in
                recorder.record(request)
                if request.url == Constants.cursorUsageURL {
                    let bearer = request.value(forHTTPHeaderField: "Authorization")
                    return bearer == "Bearer \(valid)"
                        ? Self.response(request, status: 200, body: Self.primaryBody(now: self.now))
                        : Self.response(request, status: 401)
                }
                return Self.response(request, status: 404)
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: stale,
                        refreshToken: nil,
                        source: .sqlite,
                        membershipType: "pro"
                    ),
                    CursorAuth(
                        accessToken: valid,
                        refreshToken: nil,
                        source: .keychain,
                        membershipType: nil
                    ),
                ]
            },
            now: { now },
            calendar: Self.utcCalendar
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.provider == .cursor)
        #expect(snapshot?.windows.first?.utilization == 42)
        #expect(recorder.requests.filter { $0.url == Constants.cursorUsageURL }.count == 2)
    }

    @Test func refreshesAfterUnauthorizedAndRetainsRotatedTokensOnlyInMemory() async throws {
        let original = Self.jwt(subject: "auth0|user-1", expiration: now.addingTimeInterval(3_600))
        let refreshed = Self.jwt(subject: "auth0|user-1", expiration: now.addingTimeInterval(1_800))
        let newest = Self.jwt(subject: "auth0|user-1", expiration: now.addingTimeInterval(7_200))
        let clock = TestClock(now)
        let recorder = RequestRecorder()
        let service = CursorUsageService(
            session: Self.mockSession { request in
                recorder.record(request)
                if request.url == Constants.cursorTokenRefreshURL {
                    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                    if body.contains("rotated-refresh") {
                        return Self.response(
                            request,
                            status: 200,
                            body: #"{"access_token":"\#(newest)","refresh_token":"newest-refresh"}"#
                        )
                    }
                    return Self.response(
                        request,
                        status: 200,
                        body: #"{"access_token":"\#(refreshed)","refresh_token":"rotated-refresh"}"#
                    )
                }
                if request.url == Constants.cursorUsageURL {
                    let bearer = request.value(forHTTPHeaderField: "Authorization")
                    if bearer == "Bearer \(original)" {
                        return Self.response(request, status: 401)
                    }
                    return Self.response(request, status: 200, body: Self.primaryBody(now: clock.value))
                }
                return Self.response(request, status: 404)
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: original,
                        refreshToken: "original-refresh",
                        source: .sqlite,
                        membershipType: "pro"
                    ),
                ]
            },
            now: { clock.value },
            calendar: Self.utcCalendar
        )

        #expect(try await service.fetchSnapshot()?.windows.first?.utilization == 42)
        clock.value = now.addingTimeInterval(1_600)
        #expect(try await service.fetchSnapshot()?.windows.first?.utilization == 42)

        let refreshBodies = recorder.requests
            .filter { $0.url == Constants.cursorTokenRefreshURL }
            .compactMap(\.httpBody)
            .compactMap { String(data: $0, encoding: .utf8) }
        #expect(refreshBodies.count == 2)
        guard refreshBodies.count == 2 else { return }
        #expect(refreshBodies[0].contains("original-refresh"))
        #expect(refreshBodies[1].contains("rotated-refresh"))
        let usageAuthorizations = recorder.requests
            .filter { $0.url == Constants.cursorUsageURL }
            .compactMap { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(usageAuthorizations.contains("Bearer \(refreshed)"))
        #expect(usageAuthorizations.contains("Bearer \(newest)"))
    }

    @Test func rejectsRotatedAccessTokenForDifferentSubject() async throws {
        let original = Self.jwt(subject: "auth0|local-user", expiration: now.addingTimeInterval(3_600))
        let other = Self.jwt(subject: "auth0|other-user", expiration: now.addingTimeInterval(3_600))
        let recorder = RequestRecorder()
        let service = CursorUsageService(
            session: Self.mockSession { request in
                recorder.record(request)
                if request.url == Constants.cursorUsageURL {
                    return Self.response(request, status: 401)
                }
                if request.url == Constants.cursorTokenRefreshURL {
                    return Self.response(
                        request,
                        status: 200,
                        body: #"{"access_token":"\#(other)","refresh_token":"other-refresh"}"#
                    )
                }
                return Self.response(request, status: 404)
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: original,
                        refreshToken: "refresh",
                        source: .sqlite,
                        membershipType: "pro"
                    ),
                ]
            },
            now: { now },
            calendar: Self.utcCalendar
        )

        #expect(try await service.fetchSnapshot() == nil)
        let authorizations = recorder.requests.compactMap {
            $0.value(forHTTPHeaderField: "Authorization")
        }
        #expect(authorizations.contains("Bearer \(other)") == false)
    }

    @Test func optionalPlanFailureDoesNotDiscardPrimarySnapshot() async throws {
        let token = Self.jwt(subject: "auth0|user", expiration: now.addingTimeInterval(3_600))
        let service = CursorUsageService(
            session: Self.mockSession { request in
                if request.url == Constants.cursorUsageURL {
                    return Self.response(request, status: 200, body: Self.primaryBody(now: self.now))
                }
                if request.url == Constants.cursorPlanURL {
                    return Self.response(
                        request,
                        status: 500,
                        body: #"{"token":"must-not-be-logged"}"#
                    )
                }
                return Self.response(request, status: 404)
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: token,
                        refreshToken: nil,
                        source: .sqlite,
                        membershipType: "pro"
                    ),
                ]
            },
            now: { now },
            calendar: Self.utcCalendar
        )

        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot?.windows.first?.utilization == 42)
        #expect(snapshot?.planName == nil)
    }

    @Test func validLegacyFallbackSurvivesSummaryFailure() async throws {
        let token = Self.jwt(subject: "auth0|user", expiration: now.addingTimeInterval(3_600))
        let service = CursorUsageService(
            session: Self.mockSession { request in
                if request.url == Constants.cursorUsageURL {
                    return Self.response(request, status: 200, body: "{}")
                }
                if request.url == Constants.cursorUsageSummaryURL {
                    return Self.response(request, status: 500)
                }
                if request.url?.path == Constants.cursorLegacyUsageURL.path {
                    return Self.response(
                        request,
                        status: 200,
                        body: """
                        {"gpt-4":{"numRequests":25,"maxRequestUsage":100},
                         "startOfMonth":"2027-01-01T00:00:00Z"}
                        """
                    )
                }
                return Self.response(request, status: 404)
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: token,
                        refreshToken: nil,
                        source: .sqlite,
                        membershipType: "enterprise"
                    ),
                ]
            },
            now: { now },
            calendar: Self.utcCalendar
        )

        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot?.windows.first?.windowID.rawValue == "cursor.requests")
        #expect(snapshot?.windows.first?.utilization == 25)
    }

    @Test func cursorFiveHundredsAreCredentialSafeProviderOutages() async {
        let token = Self.jwt(subject: "auth0|secret-user", expiration: now.addingTimeInterval(3_600))
        let service = CursorUsageService(
            session: Self.mockSession { request in
                Self.response(
                    request,
                    status: 503,
                    body: #"{"secret":"response-body-must-not-escape"}"#
                )
            },
            authLoader: {
                [
                    CursorAuth(
                        accessToken: token,
                        refreshToken: "secret-refresh",
                        source: .sqlite,
                        membershipType: "pro"
                    ),
                ]
            },
            now: { now },
            calendar: Self.utcCalendar
        )

        do {
            _ = try await service.fetchSnapshot()
            Issue.record("Expected Cursor 503 to be surfaced")
        } catch let error as CursorUsageService.CursorError {
            guard case .serverError(let code) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(code == 503)
            let description = error.localizedDescription
            #expect(description.contains(token) == false)
            #expect(description.contains("secret-refresh") == false)
            #expect(description.contains("response-body-must-not-escape") == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func jwtExpiryDrivesProactiveRefreshWindow() {
        let near = Self.jwt(subject: "auth0|user", expiration: now.addingTimeInterval(299))
        let far = Self.jwt(subject: "auth0|user", expiration: now.addingTimeInterval(301))
        let expired = Self.jwt(subject: "auth0|user", expiration: now.addingTimeInterval(-1))

        #expect(CursorUsageService.needsRefresh(near, now: now))
        #expect(CursorUsageService.needsRefresh(far, now: now) == false)
        #expect(CursorUsageService.isExpired(expired, now: now))
        #expect(CursorToken.subject(near) == "auth0|user")
    }

    // MARK: - Helpers

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func iso8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func jwt(subject: String, expiration: Date) -> String {
        let payload = #"{"sub":"\#(subject)","exp":\#(Int(expiration.timeIntervalSince1970))}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "header.\(encoded).signature"
    }

    private static func primaryBody(now: Date) -> String {
        let start = Int(now.addingTimeInterval(-10 * 24 * 3_600).timeIntervalSince1970 * 1_000)
        let end = Int(now.addingTimeInterval(21 * 24 * 3_600).timeIntervalSince1970 * 1_000)
        return """
        {"enabled":true,"billingCycleStart":\(start),"billingCycleEnd":\(end),
         "planUsage":{"totalPercentUsed":42}}
        """
    }

    private static func mockSession(
        _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CursorURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CursorURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String = ""
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url ?? Constants.cursorUsageURL,
                statusCode: status,
                httpVersion: "HTTP/2",
                headerFields: [:]
            )!,
            Data(body.utf8)
        )
    }

    private static func writeStateDatabase(values: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorUsageServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.vscdb")

        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw CursorTestError.sqlite
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw CursorTestError.sqlite
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (key, value) in values {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO ItemTable (key, value) VALUES (?, ?);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else {
                throw CursorTestError.sqlite
            }
            sqlite3_bind_text(statement, 1, key, -1, transient)
            sqlite3_bind_text(statement, 2, value, -1, transient)
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else {
                throw CursorTestError.sqlite
            }
        }
        return url
    }
}

private enum CursorTestError: Error {
    case sqlite
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            storedRequests.append(request)
        }
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class CursorURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        var capturedRequest = request
        if capturedRequest.httpBody == nil,
           let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            capturedRequest.httpBody = data
        }
        let (response, data) = handler(capturedRequest)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
