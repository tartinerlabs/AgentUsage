//
//  CodexUsageServiceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Synchronization
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("Codex Usage Service", .serialized)
struct CodexUsageServiceTests {
    private static let usageHost = "chatgpt.com"
    private static let refreshHost = "auth.openai.com"

    @Test func bodyWindowsAreMappedFromRateLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primaryReset = now.addingTimeInterval(8535).timeIntervalSince1970
        let weeklyReset = now.addingTimeInterval(323_863).timeIntervalSince1970
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":22,"reset_at":\(Int(primaryReset)),"limit_window_seconds":18000},"secondary_window":{"used_percent":34,"reset_at":\(Int(weeklyReset)),"limit_window_seconds":604800}}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.provider == .codex)
        #expect(snapshot?.fetchedAt == now)
        #expect(snapshot?.planName == "Pro 5x")
        #expect(snapshot?.windows.count == 2)
        let primary = try #require(snapshot?.windows.first { $0.windowType == .codexFiveHour })
        let weekly = try #require(snapshot?.windows.first { $0.windowType == .codexWeekly })
        #expect(primary.utilization == 22)
        #expect(weekly.utilization == 34)
        #expect(primary.resetsAt == Date(timeIntervalSince1970: primaryReset))
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: weeklyReset))
    }

    @Test func weeklyOnlyPrimaryWindowIsClassifiedByDuration() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyReset = now.addingTimeInterval(579_800).timeIntervalSince1970
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":16,"reset_at":\(Int(weeklyReset)),"limit_window_seconds":604800},"secondary_window":null}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.count == 1)
        let weekly = try #require(snapshot?.windows.first)
        #expect(weekly.windowType == .codexWeekly)
        #expect(weekly.displayName == "Weekly limit")
        #expect(weekly.utilization == 16)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: weeklyReset))
        #expect(snapshot?.windows.contains { $0.windowType == .codexFiveHour } == false)
    }

    @Test func durationClassificationDoesNotDependOnWindowSlot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":31,"reset_after_seconds":600,"limit_window_seconds":604800},"secondary_window":{"used_percent":42,"reset_after_seconds":1200,"limit_window_seconds":18000}}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.count == 2)
        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.utilization == 31)
        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.utilization == 42)
    }

    @Test func unknownDurationIsNotMisclassifiedByWindowSlot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":9,"limit_window_seconds":86400},"secondary_window":null}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let window = try #require(snapshot?.windows.first)
        #expect(window.windowType == .custom)
        #expect(window.displayName == "Usage limit")
        #expect(window.totalDuration == 86_400)
        #expect(window.resetsAt == now.addingTimeInterval(86_400))
    }

    @Test func headerPercentsOverrideBody() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":10,"reset_at":\(Int(now.timeIntervalSince1970 + 60)),"limit_window_seconds":604800},"secondary_window":{"used_percent":20,"reset_at":\(Int(now.timeIntervalSince1970 + 600)),"limit_window_seconds":18000}}}
        """
        let headers = [
            "x-codex-primary-used-percent": "77",
            "x-codex-secondary-used-percent": "88",
        ]

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200, headers: headers), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.utilization == 77)
        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.utilization == 88)
        #expect(snapshot?.planName == "Pro 20x")
    }

    @Test func durationlessPayloadUsesLegacySlotMapping() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"reset_after_seconds":90},"secondary_window":null}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.count == 1)
        let window = try #require(snapshot?.windows.first)
        #expect(window.windowType == .codexFiveHour)
        #expect(window.utilization == 12)
        #expect(window.resetsAt == now.addingTimeInterval(90))
        #expect(snapshot?.planName == "Plus")
    }

    @Test func unauthorizedRefreshesTokenThenSucceeds() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null}}
        """
        let counter = CallCounter()

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 404), Data())
            }
            let host = request.url?.host ?? ""
            if host == Self.refreshHost {
                counter.refreshCalls.withLock { $0 += 1 }
                return (Self.response(200), Data(#"{"access_token":"new-token"}"#.utf8))
            }
            counter.usageCalls.withLock { $0 += 1 }
            // First usage call is unauthorized; after refresh it succeeds.
            if counter.usageCalls.withLock({ $0 }) == 1 {
                return (Self.response(401), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(counter.usageCalls.withLock { $0 } == 2)
        #expect(counter.refreshCalls.withLock { $0 } == 1)
        #expect(snapshot?.windows.first?.utilization == 5)
    }

    @Test func sessionExpiredReturnsNilWithoutFabricatingZero() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = try Self.makeService(now: now) { request in
            let host = request.url?.host ?? ""
            if host == Self.refreshHost {
                return (Self.response(400), Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8))
            }
            return (Self.response(401), Data())
        }
        let snapshot = try await service.fetchSnapshot()

        // Critical anti-bug contract: no snapshot at all, never a 0% window.
        #expect(snapshot == nil)
    }

    @Test func missingAuthFileReturnsNil() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("auth.json")
        let service = CodexUsageService(
            session: Self.mockSession { _ in
                Issue.record("Network must not be hit when no auth file is present")
                return (Self.response(500), Data())
            },
            authFileURLs: [missing],
            now: { now }
        )
        let snapshot = try await service.fetchSnapshot()
        #expect(snapshot == nil)
    }

    // MARK: - Code Review, Model Quotas, and Credits

    @Test func codeReviewAndModelQuotasFollowPlanWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let review = Self.rateLimitJSON(
            primary: Self.windowJSON(usedPercent: 12, seconds: 604_800, now: now, resetsIn: 400_000),
            secondary: nil
        )
        let spark = Self.rateLimitJSON(
            primary: Self.windowJSON(usedPercent: 40, seconds: 18_000, now: now, resetsIn: 3_600),
            secondary: Self.windowJSON(usedPercent: 8, seconds: 604_800, now: now, resetsIn: 500_000)
        )
        let body = Self.usageBody(now: now, extra: """
        ,"code_review_rate_limit":\(review),"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":\(spark)}],"credits":{"has_credits":true,"unlimited":false,"balance":"1250","approx_local_messages":[20,100],"approx_cloud_messages":[5,25]}
        """)

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 404), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()
        let codex = try #require(snapshot)

        #expect(codex.windows.map(\.windowID.rawValue) == Self.planWindowIDs + [
            "codex.review.weekly",
            "codex.model.codex_spark.five_hour",
            "codex.model.codex_spark.weekly",
        ])
        #expect(codex.windows.map(\.displayName) == [
            "5-hour limit",
            "Weekly limit",
            "Code review weekly limit",
            "GPT-5.3-Codex-Spark 5-hour limit",
            "GPT-5.3-Codex-Spark weekly limit",
        ])
        // Provider-defined windows stay `.custom` so older iOS builds still decode them.
        #expect(codex.windows.dropFirst(2).allSatisfy { $0.windowType == .custom })

        let reviewWindow = try #require(codex.windows.first { $0.windowID == "codex.review.weekly" })
        #expect(reviewWindow.utilization == 12)
        #expect(reviewWindow.totalDuration == 604_800)
        #expect(reviewWindow.resetsAt == now.addingTimeInterval(400_000))
        #expect(reviewWindow.scope == nil)

        let sparkFiveHour = try #require(codex.windows.first { $0.windowID == "codex.model.codex_spark.five_hour" })
        #expect(sparkFiveHour.utilization == 40)
        #expect(sparkFiveHour.totalDuration == 18_000)
        #expect(sparkFiveHour.resetsAt == now.addingTimeInterval(3_600))
        #expect(sparkFiveHour.scope?.model == "GPT-5.3-Codex-Spark")

        let sparkWeekly = try #require(codex.windows.first { $0.windowID == "codex.model.codex_spark.weekly" })
        #expect(sparkWeekly.utilization == 8)
        #expect(sparkWeekly.resetsAt == now.addingTimeInterval(500_000))

        #expect(codex.creditBalance == CreditBalance(remaining: 1_250))
    }

    @Test func planOnlyPayloadKeepsJustThePlanWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = Self.usageBody(now: now)

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.map(\.windowID.rawValue) == Self.planWindowIDs)
        #expect(snapshot?.windows.map(\.utilization) == [22, 34])
        #expect(snapshot?.creditBalance == nil)
    }

    @Test func absentOrEmptyExtraQuotasAddNoWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let emptyRateLimit = Self.rateLimitJSON(primary: nil, secondary: nil)
        let extras = [
            #","code_review_rate_limit":null,"additional_rate_limits":null,"credits":null"#,
            #","additional_rate_limits":[]"#,
            #","additional_rate_limits":[null]"#,
            #","additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":null}]"#,
            #","additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark"}]"#,
            #","additional_rate_limits":[{"rate_limit":\#(emptyRateLimit)}]"#,
            #","code_review_rate_limit":\#(emptyRateLimit),"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":\#(emptyRateLimit)}]"#,
        ]

        for extra in extras {
            let body = Self.usageBody(now: now, extra: extra)
            let service = try Self.makeService(now: now) { _ in
                (Self.response(200), Data(body.utf8))
            }
            let snapshot = try await service.fetchSnapshot()

            #expect(snapshot?.windows.map(\.windowID.rawValue) == Self.planWindowIDs, "\(extra)")
        }
    }

    @Test func malformedExtraBlocksNeverCostThePlanWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let extras = [
            #","code_review_rate_limit":"unavailable","additional_rate_limits":{"limit_name":"GPT-5.3-Codex-Spark"},"credits":42"#,
            #","code_review_rate_limit":{"primary_window":{"used_percent":"high"}},"additional_rate_limits":[{"limit_name":7,"metered_feature":"codex_spark","rate_limit":{"primary_window":{"used_percent":"high"}}}],"credits":{"has_credits":"yes","balance":{"amount":5}}"#,
            #","additional_rate_limits":["GPT-5.3-Codex-Spark"],"credits":[]"#,
        ]

        for extra in extras {
            let body = Self.usageBody(now: now, extra: extra)
            let service = try Self.makeService(now: now) { _ in
                (Self.response(200), Data(body.utf8))
            }
            let snapshot = try await service.fetchSnapshot()

            #expect(snapshot?.windows.map(\.windowID.rawValue) == Self.planWindowIDs, "\(extra)")
            #expect(snapshot?.windows.map(\.utilization) == [22, 34], "\(extra)")
            #expect(snapshot?.creditBalance == nil, "\(extra)")
        }
    }

    @Test func extraQuotasShowWithoutPlanWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let review = Self.rateLimitJSON(
            primary: Self.windowJSON(usedPercent: 3, seconds: 604_800, now: now, resetsIn: 7_200),
            secondary: nil
        )
        let body = """
        {"plan_type":"plus","rate_limit":null,"code_review_rate_limit":\(review)}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.map(\.windowID.rawValue) == ["codex.review.weekly"])
        #expect(snapshot?.windows.first?.utilization == 3)
    }

    @Test func creditBalanceShowsWithoutRateLimitWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":null,"credits":{"has_credits":true,"unlimited":false,"balance":"300"}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()
        let codex = try #require(snapshot)

        #expect(codex.windows.isEmpty)
        #expect(codex.creditBalance == CreditBalance(remaining: 300))
    }

    @Test func payloadWithNoWindowsAndNoCreditsIsInvalid() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}
        """

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }

        await #expect(throws: CodexUsageService.CodexError.self) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func extraQuotaIdentityFollowsLengthNotSlot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Weekly review limit reported in the secondary slot.
        let review = Self.rateLimitJSON(
            primary: nil,
            secondary: Self.windowJSON(usedPercent: 5, seconds: 604_800, now: now, resetsIn: 1_000)
        )
        let threeDay = Self.rateLimitJSON(
            primary: Self.windowJSON(usedPercent: 7, seconds: 259_200, now: now, resetsIn: 2_000),
            secondary: nil
        )
        let unsized = Self.rateLimitJSON(
            primary: #"{"used_percent":9,"reset_after_seconds":90}"#,
            secondary: nil
        )
        let body = Self.usageBody(now: now, extra: """
        ,"code_review_rate_limit":\(review),"additional_rate_limits":[{"limit_name":"Model A","metered_feature":"codex_a","rate_limit":\(threeDay)},{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":\(unsized)}]
        """)

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()
        let windows = try #require(snapshot?.windows)

        #expect(windows.map(\.windowID.rawValue) == Self.planWindowIDs + [
            "codex.review.weekly",
            "codex.model.codex_a.3d",
            "codex.model.gpt_5_3_codex_spark.primary",
        ])
        #expect(windows.dropFirst(2).map(\.displayName) == [
            "Code review weekly limit",
            "Model A 3-day limit",
            "GPT-5.3-Codex-Spark limit",
        ])
        let unsizedWindow = try #require(windows.last)
        #expect(unsizedWindow.totalDuration == 0)
        #expect(unsizedWindow.resetsAt == now.addingTimeInterval(90))
    }

    @Test func repeatedModelQuotaAppearsOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let spark = Self.rateLimitJSON(
            primary: Self.windowJSON(usedPercent: 40, seconds: 18_000, now: now, resetsIn: 3_600),
            secondary: nil
        )
        let entry = #"{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":\#(spark)}"#
        let body = Self.usageBody(now: now, extra: #","additional_rate_limits":[\#(entry),\#(entry)]"#)

        let service = try Self.makeService(now: now) { _ in
            (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.map(\.windowID.rawValue) == Self.planWindowIDs + [
            "codex.model.codex_spark.five_hour",
        ])
    }

    @Test func creditsSurfaceOnlyAsUnlimitedOrAPositiveBalance() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(credits: String?, expected: CreditBalance?)] = [
            (nil, nil),
            ("null", nil),
            (#"{"has_credits":false,"unlimited":false,"balance":"0"}"#, nil),
            (#"{"has_credits":false,"unlimited":false,"balance":"25"}"#, nil),
            (#"{"has_credits":true,"unlimited":false,"balance":null}"#, nil),
            (#"{"has_credits":true,"unlimited":false,"balance":"0"}"#, nil),
            (#"{"has_credits":true,"unlimited":false,"balance":"n/a"}"#, nil),
            (#"{"has_credits":true,"unlimited":true,"balance":null}"#, .unlimited),
            (#"{"has_credits":false,"unlimited":true}"#, .unlimited),
            (#"{"has_credits":true,"unlimited":false,"balance":"9.99"}"#, CreditBalance(remaining: 9.99)),
            (#"{"has_credits":true,"unlimited":false,"balance":" 25 "}"#, CreditBalance(remaining: 25)),
            (#"{"has_credits":true,"unlimited":false,"balance":42}"#, CreditBalance(remaining: 42)),
        ]

        for (credits, expected) in cases {
            let body = Self.usageBody(now: now, extra: credits.map { #","credits":\#($0)"# } ?? "")
            let service = try Self.makeService(now: now) { _ in
                (Self.response(200), Data(body.utf8))
            }
            let snapshot = try await service.fetchSnapshot()

            #expect(snapshot?.creditBalance == expected, "credits: \(credits ?? "absent")")
            #expect(snapshot?.windows.map(\.windowID.rawValue) == Self.planWindowIDs, "credits: \(credits ?? "absent")")
        }
    }

    @Test func resetCreditsEnrichmentKeepsCreditBalance() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = Self.usageBody(now: now, extra: """
        ,"rate_limit_reset_credits":{"available_count":1},"credits":{"has_credits":true,"unlimited":false,"balance":"300"}
        """)
        let expiry = now.addingTimeInterval(2 * 86400)
        let resetBody = """
        {"available_count":1,"credits":[{"status":"available","expires_at":"\(Self.iso8601(expiry))"}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.rateLimitResetCredits?.expirations == [expiry])
        #expect(snapshot?.creditBalance == CreditBalance(remaining: 300))
    }

    // MARK: - Reset Credits

    @Test func resetCreditsCountParsedFromUsageBody() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 404), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 3)
        #expect(credits.expirations.isEmpty)
    }

    @Test func resetCreditsDetailsEnrichExpirations() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":22,"reset_at":\(Int(now.timeIntervalSince1970 + 3600))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":2}}
        """
        let expiry1 = now.addingTimeInterval(3 * 86400)
        let expiry2 = now.addingTimeInterval(7 * 86400)
        let resetBody = """
        {"available_count":2,"credits":[{"status":"available","expires_at":"\(Self.iso8601(expiry2))"},{"status":"available","expires_at":"\(Self.iso8601(expiry1))"}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 2)
        #expect(credits.expirations.count == 2)
        #expect(credits.expirations == [expiry1, expiry2].sorted())
    }

    @Test func resetCreditsDetailsFailureFallsBackToCount() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 500), Data())
            }
            return (Self.response(200), Data(body.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.availableCount == 3)
        #expect(credits.expirations.isEmpty)
    }

    @Test func resetCreditsDetailsSendsExpectedHeaders() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":1}}
        """
        let capture = HeaderCapture()

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                capture.openAIBeta.withLock { $0 = request.value(forHTTPHeaderField: "OpenAI-Beta") }
                capture.originator.withLock { $0 = request.value(forHTTPHeaderField: "originator") }
                capture.authorization.withLock { $0 = request.value(forHTTPHeaderField: "Authorization") }
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(#"{"available_count":1,"credits":[]}"#.utf8))
            }
            return (Self.response(200), Data(body.utf8))
        }
        _ = try await service.fetchSnapshot()

        #expect(capture.openAIBeta.withLock { $0 } == "codex-1")
        #expect(capture.originator.withLock { $0 } == "Codex Desktop")
        #expect(capture.authorization.withLock { $0 } == "Bearer test-access")
    }

    @Test func resetCreditsFiltersNonAvailableCredits() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":3}}
        """
        let availableExpiry = now.addingTimeInterval(5 * 86400)
        let resetBody = """
        {"available_count":3,"credits":[{"status":"available","expires_at":"\(Self.iso8601(availableExpiry))"},{"status":"consumed","expires_at":"\(Self.iso8601(now.addingTimeInterval(86400)))"},{"status":"expired","expires_at":"\(Self.iso8601(now.addingTimeInterval(86400)))"},{"status":"available","expires_at":"\(Self.iso8601(now.addingTimeInterval(10 * 86400)))"}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.expirations.count == 2)
        #expect(credits.expirations == [availableExpiry, now.addingTimeInterval(10 * 86400)].sorted())
    }

    @Test func resetCreditsParsesEpochExpiresAt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usageBody = """
        {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":5,"reset_at":\(Int(now.timeIntervalSince1970 + 60))},"secondary_window":null},"rate_limit_reset_credits":{"available_count":1}}
        """
        let epochExpiry = now.addingTimeInterval(6 * 86400).timeIntervalSince1970
        let resetBody = """
        {"available_count":1,"credits":[{"status":"available","expires_at":\(epochExpiry)}]}
        """

        let service = try Self.makeService(now: now) { request in
            if Self.isResetCreditsPath(request) {
                return (Self.response(url: Constants.codexResetCreditsURL, 200), Data(resetBody.utf8))
            }
            return (Self.response(200), Data(usageBody.utf8))
        }
        let snapshot = try await service.fetchSnapshot()

        let credits = try #require(snapshot?.rateLimitResetCredits)
        #expect(credits.expirations.count == 1)
        #expect(credits.expirations.first == Date(timeIntervalSince1970: epochExpiry))
    }

    // MARK: - Helpers

    private final class CallCounter: Sendable {
        let usageCalls = Mutex(0)
        let refreshCalls = Mutex(0)
    }

    private final class HeaderCapture: Sendable {
        let openAIBeta = Mutex<String?>(nil)
        let originator = Mutex<String?>(nil)
        let authorization = Mutex<String?>(nil)
    }

    private static let planWindowIDs = [
        UsageWindowType.codexFiveHour.rawValue,
        UsageWindowType.codexWeekly.rawValue,
    ]

    /// A window shaped like Codex's `RateLimitWindowSnapshot`.
    private static func windowJSON(usedPercent: Int, seconds: Int, now: Date, resetsIn: Int) -> String {
        """
        {"used_percent":\(usedPercent),"limit_window_seconds":\(seconds),"reset_after_seconds":\(resetsIn),"reset_at":\(Int(now.timeIntervalSince1970) + resetsIn)}
        """
    }

    /// A quota shaped like Codex's `RateLimitStatusDetails`.
    private static func rateLimitJSON(primary: String?, secondary: String?) -> String {
        """
        {"allowed":true,"limit_reached":false,"primary_window":\(primary ?? "null"),"secondary_window":\(secondary ?? "null")}
        """
    }

    /// A `/wham/usage` body shaped like Codex's `RateLimitStatusPayload`: the plan's
    /// 5-hour (22%) and weekly (34%) windows, then `extra` top-level members.
    private static func usageBody(now: Date, extra: String = "") -> String {
        let plan = rateLimitJSON(
            primary: windowJSON(usedPercent: 22, seconds: 18_000, now: now, resetsIn: 8_535),
            secondary: windowJSON(usedPercent: 34, seconds: 604_800, now: now, resetsIn: 323_863)
        )
        return """
        {"plan_type":"pro","rate_limit":\(plan),"spend_control":null,"rate_limit_reached_type":null\(extra)}
        """
    }

    private static func isResetCreditsPath(_ request: URLRequest) -> Bool {
        (request.url?.path ?? "").contains("rate-limit-reset-credits")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func makeService(
        now: Date,
        handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) throws -> CodexUsageService {
        let authURL = try writeAuthFile()
        return CodexUsageService(
            session: mockSession(handler),
            authFileURLs: [authURL],
            now: { now }
        )
    }

    private static func mockSession(
        _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CodexURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        Self.response(url: Constants.codexUsageURL, status, headers: headers)
    }

    private static func response(url: URL, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: headers
        )!
    }

    private static func writeAuthFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageServiceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("auth.json")
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"test-access","refresh_token":"test-refresh","account_id":"test-account"}}
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private final class CodexURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
