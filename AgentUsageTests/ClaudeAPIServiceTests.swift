//
//  ClaudeAPIServiceTests.swift
//  AgentUsageTests
//
//  Tests for ClaudeAPIService JSON parsing and response handling
//

import Testing
import Foundation
@testable import AgentUsage
@testable import AgentUsageKit

// MARK: - ClaudeAPIService Response Parsing Tests

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    // MARK: - API Error Tests

    @Test func unauthorizedErrorDescription() {
        let error = ClaudeAPIService.APIError.unauthorized
        #expect(error.errorDescription?.contains("Unauthorized") == true)
        #expect(error.errorDescription?.contains("re-authenticate") == true)
    }

    @Test func networkErrorDescription() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        let error = ClaudeAPIService.APIError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network error") == true)
    }

    @Test func invalidResponseErrorDescription() {
        let error = ClaudeAPIService.APIError.invalidResponse
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }

    @Test func serverErrorDescription() {
        let error = ClaudeAPIService.APIError.serverError(500)
        #expect(error.errorDescription?.contains("500") == true)
    }

    @Test func mapsUsageSnapshotToProviderUsageSnapshot() {
        let fetchedAt = Date()
        let snapshot = UsageSnapshot(
            session: UsageWindow(
                utilization: 12,
                resetsAt: fetchedAt.addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 34,
                resetsAt: fetchedAt.addingTimeInterval(7_200),
                windowType: .opus
            ),
            sonnet: nil,
            extraUsage: ExtraUsageCost(used: 1.5, limit: 10, currencyCode: "USD"),
            fetchedAt: fetchedAt
        )
        let effort = EffortPeriodSummary(
            period: .last30Days,
            levels: [EffortLevelCount(level: .high, sessionCount: 2)],
            classifiedSessionCount: 2,
            unclassifiedSessionCount: 0
        )

        let mapped = ClaudeAPIService.providerSnapshot(
            from: snapshot,
            planName: "Max",
            effortSummaries: [effort]
        )

        #expect(mapped.provider == .claude)
        #expect(mapped.planName == "Max")
        #expect(mapped.windows.map(\.windowType) == [.session, .opus])
        #expect(mapped.windows.map(\.utilization) == [12, 34])
        #expect(mapped.extraUsage?.used == 1.5)
        #expect(mapped.effortSummaries == [effort])
        #expect(mapped.fetchedAt == fetchedAt)
        #expect(mapped.rateLimitResetCredits == nil)
    }

    @Test func bridgeCarriesBankedResets() {
        let fetchedAt = Date()
        let credits = RateLimitResetCredits(availableCount: 1, expirations: [fetchedAt.addingTimeInterval(86_400)])
        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 12, resetsAt: fetchedAt, windowType: .session),
            opus: UsageWindow(utilization: 34, resetsAt: fetchedAt, windowType: .opus),
            sonnet: nil,
            rateLimitResetCredits: credits,
            fetchedAt: fetchedAt
        )

        #expect(ClaudeAPIService.providerSnapshot(from: snapshot).rateLimitResetCredits == credits)
    }

    // MARK: - Banked Resets (cedar_ember)

    /// Grant shape observed on `/usage?cedar_ember=1`, 2026-09-22.
    private static let launchGrant = """
    {"id": "opus55-launch-promax-20260921",
     "label": "Claude Opus 5.5 launch: one usage-limit reset for Pro and Max",
     "resets_total": 1, "resets_left": 1,
     "starts_at": "2026-09-22T16:00:00+00:00", "ends_at": "2026-10-22T16:00:00+00:00",
     "clears": ["five_hour", "seven_day"], "paused": false, "usable_now": true,
     "use_requires_limit": false, "blocking": []}
    """

    private static let now = ISO8601DateFormatter().date(from: "2026-09-23T00:00:00Z")!

    private func bankedResets(_ grants: String) throws -> RateLimitResetCredits? {
        let json = """
        {"eligible": true, "ineligible_reason": null, "at_limit": false, "exhausted": [],
         "grants": [\(grants)], "next_grant_id": null, "weekly_resets_at": null, "cooldown_until": null}
        """
        let response = try JSONDecoder().decode(ClaudeAPIService.CedarEmberResponse.self, from: Data(json.utf8))
        return ClaudeAPIService.resetCredits(from: response, now: Self.now)
    }

    @Test func bankedResetParsedWithExpiry() throws {
        let credits = try #require(try bankedResets(Self.launchGrant))
        #expect(credits.availableCount == 1)
        #expect(credits.expirations == [ISO8601DateFormatter().date(from: "2026-10-22T16:00:00Z")!])
    }

    @Test func multipleResetsInOneGrantCountSeparately() throws {
        let two = Self.launchGrant.replacingOccurrences(of: "\"resets_left\": 1", with: "\"resets_left\": 2")
        let credits = try #require(try bankedResets(two))
        #expect(credits.availableCount == 2)
        #expect(credits.expirations.count == 2)
    }

    @Test func spentPausedAndExpiredGrantsBankNothing() throws {
        let spent = Self.launchGrant.replacingOccurrences(of: "\"resets_left\": 1", with: "\"resets_left\": 0")
        let paused = Self.launchGrant.replacingOccurrences(of: "\"paused\": false", with: "\"paused\": true")
        let expired = Self.launchGrant.replacingOccurrences(of: "2026-10-22T16:00:00+00:00", with: "2026-09-22T20:00:00+00:00")
        for grant in [spent, paused, expired] {
            #expect(try bankedResets(grant) == nil)
        }
    }

    @Test func ineligibleAccountHasNoBankedResets() throws {
        #expect(try bankedResets("") == nil)
    }

    // MARK: - Full Response (real parser)

    /// Trimmed from a live `/api/oauth/usage?cedar_ember=1` body, 2026-09-24.
    private static let liveResponse = """
    {
      "five_hour": {"utilization": 9.0, "resets_at": "2026-09-24T11:39:59.671160+00:00",
                    "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
      "seven_day": {"utilization": 22.0, "resets_at": "2026-09-30T07:59:59.671179+00:00",
                    "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
      "seven_day_oauth_apps": null, "seven_day_opus": null, "seven_day_sonnet": null,
      "seven_day_cowork": null, "seven_day_omelette": null, "tangelo": null,
      "iguana_necktie": {"utilization": 0.9884844, "resets_at": "2026-11-05T07:59:00+00:00",
                         "limit_dollars": 250, "used_dollars": 2.471211, "remaining_dollars": 247.528789, "locked_reason": null},
      "nimbus_quill": {"utilization": 0.0, "resets_at": null, "limit_dollars": null,
                       "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
      "cinder_cove": null,
      "cedar_ember": {"eligible": true, "ineligible_reason": null, "at_limit": false, "exhausted": [],
                      "grants": [\(launchGrant)], "next_grant_id": "opus55-launch-promax-20260921",
                      "weekly_resets_at": "2026-09-30T08:00:00+00:00", "cooldown_until": null},
      "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null,
                      "currency": null, "disabled_reason": null, "user_disabled": true},
      "limits": [
        {"kind": "session", "group": "session", "percent": 9, "severity": "normal",
         "resets_at": "2026-09-24T11:39:59.671160+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_all", "group": "weekly", "percent": 22, "severity": "normal",
         "resets_at": "2026-09-30T07:59:59.671179+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
         "resets_at": "2026-09-30T08:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ],
      "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "limit": null,
                "percent": 0, "severity": "normal", "enabled": false},
      "member_dashboard_available": false,
      "seven_day_breakdown": {"as_of": "2026-09-24T07:36:59.752118+00:00",
        "window_started_at": "2026-09-23T07:59:59.671179+00:00",
        "rows": [{"key": "claude_code", "display_name": "Claude Code", "percent": 100},
                 {"key": "chat", "display_name": "Chats", "percent": 0}]}
    }
    """

    private func parse(_ json: String) async throws -> UsageSnapshot {
        try await ClaudeAPIService().parseUsageResponse(Data(json.utf8))
    }

    @Test func parsesLiveResponse() async throws {
        let snapshot = try await parse(Self.liveResponse)

        #expect(snapshot.session.utilization == 9)
        #expect(snapshot.session.serverStatus == .onTrack)
        #expect(snapshot.opus.utilization == 22)
        #expect(snapshot.sonnet == nil)
        #expect(snapshot.fable?.utilization == 0)
        #expect(snapshot.extraUsage == nil)

        // iguana_necktie is a dollar budget; nimbus_quill is an empty placeholder.
        #expect(snapshot.additionalWindows.map(\.windowID.rawValue) == ["claude.iguana_necktie"])
        let credit = try #require(snapshot.additionalWindows.first)
        #expect(credit.displayName == "Usage credit")
        #expect(credit.budget?.limit == 250)
        #expect(credit.budget?.used == 2.471211)
        #expect(credit.windowType == .custom)

        #expect(snapshot.weeklyBreakdown.map(\.key) == ["claude_code", "chat"])
        #expect(snapshot.weeklyBreakdown.first?.percent == 100)

        let credits = try #require(snapshot.rateLimitResetCredits)
        #expect(credits.grantLabels == ["Claude Opus 5.5 launch: one usage-limit reset for Pro and Max"])

        let bridged = ClaudeAPIService.providerSnapshot(from: snapshot)
        #expect(bridged.windows.map(\.windowID.rawValue) == ["session", "opus", "fable", "claude.iguana_necktie"])
        #expect(bridged.usageBreakdown == snapshot.weeklyBreakdown)
    }

    @Test func parsesScopedRowsCreditsAndServerSeverity() async throws {
        let json = """
        {
          "five_hour": {"utilization": 40, "resets_at": "2099-01-01T00:00:00Z"},
          "seven_day": {"utilization": 10, "resets_at": "2099-01-01T00:00:00Z", "locked_reason": "seat_removed"},
          "seven_day_opus": {"utilization": 30, "resets_at": "2099-01-01T00:00:00Z"},
          "cinder_cove": {"utilization": 50, "resets_at": "2099-01-01T00:00:00Z",
                          "limit_dollars": 100, "used_dollars": 50},
          "limits": [
            {"kind": "session", "group": "session", "percent": 40, "severity": "critical", "resets_at": "2099-01-01T00:00:00Z"},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 12, "severity": "warning",
             "resets_at": "2099-01-01T00:00:00Z", "scope": {"model": null, "surface": {"display_name": "Cowork"}}},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 5, "severity": "normal",
             "resets_at": "2099-01-01T00:00:00Z", "scope": {"model": {"display_name": "Sonnet"}}}
          ]
        }
        """
        let snapshot = try await parse(json)

        // Server severity floors the local pace status.
        #expect(snapshot.session.status == .critical)
        #expect(snapshot.opus.lockedReason == "seat_removed")
        // A Sonnet row with no seven_day_sonnet key still fills the fixed Sonnet window.
        #expect(snapshot.sonnet?.utilization == 5)

        let names = snapshot.additionalWindows.map(\.displayName)
        #expect(names == ["Cowork", "Opus", "Claude Code and Cowork credit"])
        let cowork = snapshot.additionalWindows[0]
        #expect(cowork.serverStatus == .warning)
        #expect(cowork.totalDuration == UsageWindowType.opus.totalDuration)

        let credit = snapshot.additionalWindows[2]
        #expect(credit.isOneTime)
        #expect(credit.budget?.used == 50)
        #expect(credit.resetDescription().hasPrefix("Expires in"))
    }

    @Test func spendBlockBackfillsExtraUsage() async throws {
        let json = """
        {"five_hour": {"utilization": 1, "resets_at": "2099-01-01T00:00:00Z"},
         "extra_usage": {"is_enabled": false},
         "spend": {"enabled": true, "used": {"amount_minor": 1234, "currency": "USD", "exponent": 2},
                   "limit": {"amount_minor": 5000, "currency": "USD", "exponent": 2}}}
        """
        let extra = try #require(try await parse(json).extraUsage)
        #expect(extra.used == 12.34)
        #expect(extra.limit == 50)
    }

    @Test func snapshotWithoutNewFieldsStillDecodes() throws {
        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 1, resetsAt: Self.now, windowType: .session),
            opus: UsageWindow(utilization: 2, resetsAt: Self.now, windowType: .opus),
            sonnet: nil,
            additionalWindows: [UsageWindow(
                utilization: 3, resetsAt: Self.now, windowID: "claude.x", displayName: "X",
                totalDuration: 0, budget: ExtraUsageCost(used: 1, limit: 4, currencyCode: "USD"), isOneTime: true
            )],
            weeklyBreakdown: [UsageShare(key: "chat", displayName: "Chats", percent: 5)],
            fetchedAt: Self.now
        )
        let encoder = JSONEncoder()
        let roundTripped = try JSONDecoder().decode(UsageSnapshot.self, from: encoder.encode(snapshot))
        #expect(roundTripped.additionalWindows.first?.budget?.limit == 4)
        #expect(roundTripped.additionalWindows.first?.isOneTime == true)
        #expect(roundTripped.weeklyBreakdown == snapshot.weeklyBreakdown)

        // Older app versions synced snapshots without the new keys.
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        legacy["additionalWindows"] = nil
        legacy["weeklyBreakdown"] = nil
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.additionalWindows.isEmpty)
        #expect(decoded.weeklyBreakdown.isEmpty)
    }

    // MARK: - Claude Code Version (User-Agent)

    #if os(macOS)
    @Test func claudeCodeVersionPicksHighestSessionVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (pid, version) in [("1", "2.1.99"), ("2", "2.1.280"), ("3", "2.1.9")] {
            try Data(#"{"pid": \#(pid), "version": "\#(version)"}"#.utf8)
                .write(to: directory.appendingPathComponent("\(pid).json"))
        }
        try Data("not json".utf8).write(to: directory.appendingPathComponent("4.key"))

        #expect(ClaudeAPIService.claudeCodeVersion(sessionsDirectory: directory) == "2.1.280")
    }

    @Test func claudeCodeVersionFallsBackWithoutSessions() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(ClaudeAPIService.claudeCodeVersion(sessionsDirectory: missing) == Constants.claudeCodeVersionFallback)
    }
    #endif
}

// MARK: - API Response Parsing Tests

/// Tests for parsing the Claude API usage response JSON
/// These tests verify the parsing logic without making network requests
@Suite("API Response Parsing")
struct APIResponseParsingTests {

    /// Helper to parse JSON response using the same logic as ClaudeAPIService
    private func parseUsageResponse(_ json: String) throws -> UsageSnapshot {
        struct APIResponse: Decodable {
            let fiveHour: UsageWindowResponse?
            let sevenDay: UsageWindowResponse?
            let sevenDaySonnet: UsageWindowResponse?
            let limits: [LimitEntry]?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
                case sevenDaySonnet = "seven_day_sonnet"
                case limits
            }
        }

        struct UsageWindowResponse: Decodable {
            let utilization: Double
            let resetsAt: String

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        struct LimitEntry: Decodable {
            let kind: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?

            struct Scope: Decodable {
                let model: Model?

                struct Model: Decodable {
                    let displayName: String?

                    enum CodingKeys: String, CodingKey {
                        case displayName = "display_name"
                    }
                }
            }

            enum CodingKeys: String, CodingKey {
                case kind
                case percent
                case resetsAt = "resets_at"
                case scope
            }
        }

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse.self, from: data)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = response.fiveHour.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .session
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .session)

        let opus = response.sevenDay.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .opus
            )
        } ?? UsageWindow(utilization: 0, resetsAt: Date(), windowType: .opus)

        let sonnet = response.sevenDaySonnet.map {
            UsageWindow(
                utilization: $0.utilization,
                resetsAt: dateFormatter.date(from: $0.resetsAt) ?? Date(),
                windowType: .sonnet
            )
        }

        let fable = response.limits?
            .first { ($0.scope?.model?.displayName ?? "").caseInsensitiveCompare("Fable") == .orderedSame }
            .map {
                UsageWindow(
                    utilization: $0.percent ?? 0,
                    resetsAt: dateFormatter.date(from: $0.resetsAt ?? "") ?? Date(),
                    windowType: .fable
                )
            }

        return UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: sonnet,
            fable: fable,
            fetchedAt: Date()
        )
    }

    @Test func parsesCompleteResponse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 45.5,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 32.1,
                "resets_at": "2024-01-20T00:00:00.000Z"
            },
            "seven_day_sonnet": {
                "utilization": 28.7,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 45.5)
        #expect(snapshot.session.windowType == .session)
        #expect(snapshot.opus.utilization == 32.1)
        #expect(snapshot.opus.windowType == .opus)
        #expect(snapshot.sonnet?.utilization == 28.7)
        #expect(snapshot.sonnet?.windowType == .sonnet)
    }

    @Test func parsesResponseWithoutSonnet() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 50.0)
        #expect(snapshot.opus.utilization == 40.0)
        #expect(snapshot.sonnet == nil)
    }

    @Test func parsesFableFromLimitsArray() throws {
        // Fable has no dedicated top-level key; it arrives in the `limits` array
        // as a weekly-scoped entry whose model display name is "Fable".
        let json = """
        {
            "five_hour": {
                "utilization": 9.0,
                "resets_at": "2026-07-02T20:20:00.332945Z"
            },
            "seven_day": {
                "utilization": 11.0,
                "resets_at": "2026-07-08T08:00:00.332967Z"
            },
            "limits": [
                { "kind": "session", "percent": 9, "resets_at": "2026-07-02T20:20:00.332945Z", "scope": null },
                { "kind": "weekly_all", "percent": 11, "resets_at": "2026-07-08T08:00:00.332967Z", "scope": null },
                { "kind": "weekly_scoped", "percent": 16, "resets_at": "2026-07-08T08:00:00.333287Z",
                  "scope": { "model": { "id": null, "display_name": "Fable" } } }
            ]
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.fable?.utilization == 16)
        #expect(snapshot.fable?.windowType == .fable)
        #expect(snapshot.opus.utilization == 11.0)
    }

    @Test func parsesResponseWithoutFable() throws {
        // No Fable-scoped entry in limits → fable window is nil.
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            },
            "limits": [
                { "kind": "session", "percent": 50, "resets_at": "2024-01-15T18:30:00.000Z", "scope": null }
            ]
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.fable == nil)
    }

    @Test func parsesResponseAt100Percent() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 100.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 100.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.opus.isAtLimit == true)
    }

    @Test func parsesResponseWithZeroUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 0.0)
        #expect(snapshot.opus.utilization == 0.0)
        #expect(snapshot.session.isAtLimit == false)
    }

    @Test func parsesEmptyResponse() throws {
        let json = "{}"

        let snapshot = try parseUsageResponse(json)

        // Should default to zero utilization
        #expect(snapshot.session.utilization == 0)
        #expect(snapshot.opus.utilization == 0)
        #expect(snapshot.sonnet == nil)
    }

    @Test func parsesISO8601DateWithFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:45.123Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T12:00:00.456Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        // Verify dates were parsed (not default Date())
        // The exact values depend on parsing, but they should be in 2024
        let calendar = Calendar.current
        let sessionYear = calendar.component(.year, from: snapshot.session.resetsAt)
        let opusYear = calendar.component(.year, from: snapshot.opus.resetsAt)

        #expect(sessionYear == 2024)
        #expect(opusYear == 2024)
    }

    @Test func handlesUtilizationAbove100() throws {
        // API might return values > 100 in edge cases (extra usage)
        let json = """
        {
            "five_hour": {
                "utilization": 105.5,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 110.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 105.5)
        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.session.normalized == 1.0) // Clamped to 1.0
        #expect(snapshot.session.isUsingExtraUsage == true)
        #expect(snapshot.session.extraUsagePercent == 5)
        #expect(snapshot.opus.isUsingExtraUsage == true)
        #expect(snapshot.opus.extraUsagePercent == 10)
        #expect(snapshot.isExtraUsageActive == true)
    }

    @Test func handlesDecimalUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 33.333333,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 66.666666,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 33.333333)
        #expect(snapshot.session.percentUsed == 33) // Truncated
        #expect(snapshot.opus.utilization == 66.666666)
        #expect(snapshot.opus.percentUsed == 66)
    }

    // MARK: - Edge Case Tests

    @Test func handlesNegativeUtilization() throws {
        // API shouldn't return negative, but test defensive handling
        let json = """
        {
            "five_hour": {
                "utilization": -5.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        // Negative utilization is stored as-is (data model doesn't clamp)
        #expect(snapshot.session.utilization == -5.0)
        // normalized should clamp to 0
        #expect(snapshot.session.normalized == 0.0)
    }

    @Test func handlesVeryLargeUtilization() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 9999.99,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 100.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 9999.99)
        #expect(snapshot.session.isAtLimit == true)
        #expect(snapshot.session.normalized == 1.0) // Clamped
    }

    @Test func handlesExactBoundaryValues() throws {
        // Test exactly 75% (warning threshold) and 90% (critical threshold)
        let json = """
        {
            "five_hour": {
                "utilization": 75.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 90.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let snapshot = try parseUsageResponse(json)

        #expect(snapshot.session.utilization == 75.0)
        #expect(snapshot.opus.utilization == 90.0)
    }

    @Test func snapshotFetchedAtIsReasonable() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "2024-01-15T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 40.0,
                "resets_at": "2024-01-20T00:00:00.000Z"
            }
        }
        """

        let beforeParse = Date()
        let snapshot = try parseUsageResponse(json)
        let afterParse = Date()

        // fetchedAt should be between beforeParse and afterParse
        #expect(snapshot.fetchedAt >= beforeParse)
        #expect(snapshot.fetchedAt <= afterParse)
    }
}
