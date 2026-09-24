//
//  DeviceUsageMergeTests.swift
//  AgentUsageTests
//

import Testing
import Foundation
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("DeviceUsageMerge")
struct DeviceUsageMergeTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!

    @Test func ledgerLeavesOutDetailsWithoutUsage() {
        let effortOnly = ProviderDetail(
            today: Self.summary(0, period: .today),
            yesterday: Self.summary(0, period: .today),
            last30Days: Self.summary(0, period: .last30Days),
            byModel: [:],
            dailyCosts: [],
            hasTokenUsage: false
        )

        let ledger = DeviceUsageMerge.ledger(
            deviceID: "a",
            deviceName: "Studio",
            details: [.claude: Self.detail(today: 2), .codex: effortOnly],
            now: Self.now,
            calendar: Self.calendar
        )

        #expect(ledger.anchorDay == "2026-03-10")
        #expect(ledger.providers.map(\.provider) == [.claude])
        #expect(ledger.provider(.claude)?.today.tokens.input == 100)
    }

    @Test func sameDayLedgersAreSummed() throws {
        let ledgers = [
            Self.ledger(id: "a", details: [.claude: Self.detail(today: 2, yesterday: 1, month: 10)]),
            Self.ledger(id: "b", details: [.claude: Self.detail(today: 3, yesterday: 4, month: 20)]),
        ]

        let merged = try #require(
            DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar)
        )

        #expect(merged.today.costUSD == 5)
        #expect(merged.yesterday.costUSD == 5)
        #expect(merged.last30Days.costUSD == 30)
        #expect(merged.today.tokens.inputTokens == 200)
        #expect(merged.byModel["claude-opus"]?.inputTokens == 200)
        #expect(merged.dailyCosts.count == 30)
        #expect(merged.dailyCosts.last == 5)
        #expect(merged.hasTokenUsage)
    }

    @Test func yesterdaysLedgerShiftsOneDay() throws {
        let yesterday = Self.calendar.date(byAdding: .day, value: -1, to: Self.now)!
        let ledgers = [
            Self.ledger(id: "a", details: [.claude: Self.detail(today: 2, yesterday: 1, month: 10)], at: yesterday),
        ]

        let merged = try #require(
            DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar)
        )

        #expect(merged.today.costUSD == 0)
        #expect(merged.yesterday.costUSD == 2)
        #expect(merged.last30Days.costUSD == 10)
        #expect(merged.dailyCosts.last == 0)
        #expect(merged.dailyCosts[28] == 2)
    }

    @Test func ledgersOlderThanThirtyDaysAreIgnored() {
        let old = Self.calendar.date(byAdding: .day, value: -30, to: Self.now)!
        let ledgers = [Self.ledger(id: "a", details: [.claude: Self.detail(today: 2)], at: old)]

        #expect(DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func missingProviderIsNil() {
        let ledgers = [Self.ledger(id: "a", details: [.claude: Self.detail(today: 2)])]

        #expect(DeviceUsageMerge.detail(for: .codex, from: ledgers, now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func ledgerKeepsEffortOnlyProviders() throws {
        let effortOnly = ProviderDetail(
            today: Self.summary(0, period: .today),
            yesterday: Self.summary(0, period: .today),
            last30Days: Self.summary(0, period: .last30Days),
            byModel: [:],
            dailyCosts: [],
            effortSummaries: [Self.effort(.last30Days, high: 2)],
            hasTokenUsage: false
        )

        let ledger = Self.ledger(id: "a", details: [.codex: effortOnly])
        let entry = try #require(ledger.provider(.codex))

        #expect(entry.hasTokenUsage == false)
        #expect(entry.effortSummaries == [Self.effort(.last30Days, high: 2)])
    }

    @Test func effortSessionsAddUpAcrossMacs() throws {
        let ledgers = [
            Self.ledger(id: "a", details: [.claude: Self.detail(today: 1, effort: [
                Self.effort(.today, high: 1),
                Self.effort(.last30Days, high: 3, unclassified: 1),
            ])]),
            Self.ledger(id: "b", details: [.claude: Self.detail(today: 1, effort: [
                Self.effort(.last30Days, high: 2, max: 4),
            ])]),
        ]

        let merged = try #require(
            DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar)
        )
        let month = try #require(merged.effortSummary(for: .last30Days))

        #expect(merged.effortSummary(for: .today)?.totalSessionCount == 1)
        #expect(month.sessionCount(for: .high) == 5)
        #expect(month.sessionCount(for: .max) == 4)
        #expect(month.levels.map(\.level) == [.high, .max])
        #expect(month.classifiedSessionCount == 9)
        #expect(month.unclassifiedSessionCount == 1)
    }

    @Test func staleLedgerLeavesShortEffortPeriodsFirst() throws {
        let lastWeek = Self.calendar.date(byAdding: .day, value: -8, to: Self.now)!
        let ledgers = [
            Self.ledger(id: "a", details: [.claude: Self.detail(today: 1, effort: [
                Self.effort(.today, high: 1),
                Self.effort(.last7Days, high: 2),
                Self.effort(.last30Days, high: 3),
            ])], at: lastWeek),
        ]

        let merged = try #require(
            DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar)
        )

        #expect(merged.effortSummary(for: .today) == nil)
        #expect(merged.effortSummary(for: .last7Days) == nil)
        #expect(merged.effortSummary(for: .last30Days)?.totalSessionCount == 3)
    }

    @Test func effortOutlivesThirtyDayTokenWindow() throws {
        let old = Self.calendar.date(byAdding: .day, value: -40, to: Self.now)!
        let ledgers = [
            Self.ledger(id: "a", details: [.claude: Self.detail(today: 1, effort: [
                Self.effort(.last30Days, high: 3),
                Self.effort(.last90Days, high: 5),
            ])], at: old),
        ]

        let merged = try #require(
            DeviceUsageMerge.detail(for: .claude, from: ledgers, now: Self.now, calendar: Self.calendar)
        )

        #expect(merged.hasTokenUsage == false)
        #expect(merged.dailyCosts.isEmpty)
        #expect(merged.effortSummary(for: .last30Days) == nil)
        #expect(merged.effortSummary(for: .last90Days)?.totalSessionCount == 5)
    }

    @Test func usageSourceSelectionRoundTrips() {
        #expect(UsageSourceSelection(rawValue: UsageSourceSelection.allMacs.rawValue) == .allMacs)
        #expect(UsageSourceSelection(rawValue: UsageSourceSelection.mac(id: "x").rawValue) == .mac(id: "x"))
        #expect(UsageSourceSelection(rawValue: "mac:") == nil)
        #expect(UsageSourceSelection(rawValue: "bogus") == nil)
    }

    private static func ledger(
        id: String,
        details: [Provider: ProviderDetail],
        at date: Date? = nil
    ) -> DeviceUsageLedger {
        DeviceUsageMerge.ledger(
            deviceID: id,
            deviceName: id,
            details: details,
            now: date ?? now,
            calendar: calendar
        )
    }

    private static func effort(
        _ period: EffortPeriod,
        high: Int = 0,
        max: Int = 0,
        unclassified: Int = 0
    ) -> EffortPeriodSummary {
        let levels = [
            EffortLevelCount(level: .high, sessionCount: high),
            EffortLevelCount(level: .max, sessionCount: max),
        ].filter { $0.sessionCount > 0 }
        return EffortPeriodSummary(
            period: period,
            levels: levels,
            classifiedSessionCount: high + max,
            unclassifiedSessionCount: unclassified
        )
    }

    private static func detail(
        today: Double,
        yesterday: Double = 0,
        month: Double = 10,
        effort: [EffortPeriodSummary] = []
    ) -> ProviderDetail {
        var dailyCosts = Array(repeating: 0.0, count: 30)
        dailyCosts[28] = yesterday
        dailyCosts[29] = today
        return ProviderDetail(
            today: summary(today, period: .today),
            yesterday: summary(yesterday, period: .today),
            last30Days: summary(month, period: .last30Days),
            byModel: ["claude-opus": tokens],
            dailyCosts: dailyCosts,
            effortSummaries: effort
        )
    }

    private static let tokens = TokenCount(
        inputTokens: 100,
        outputTokens: 10,
        cacheCreationTokens: 0,
        cacheReadTokens: 0
    )

    private static func summary(_ cost: Double, period: UsagePeriod) -> TokenUsageSummary {
        TokenUsageSummary(tokens: tokens, costUSD: cost, period: period)
    }
}
