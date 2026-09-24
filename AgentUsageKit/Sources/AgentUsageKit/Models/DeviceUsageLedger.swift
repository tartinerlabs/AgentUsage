//
//  DeviceUsageLedger.swift
//  AgentUsageKit
//
//  Local token and cost usage one Mac read from its own CLI logs.
//
//  Quota windows are account-wide, so any Mac's fetch is the whole truth and
//  the freshest one travels in the shared snapshot. Token and cost usage is
//  not: each Mac only sees the logs written on it. Every Mac therefore
//  publishes its own ledger, and readers combine them into "All Macs" totals
//  or show one Mac on its own.
//

import Foundation

/// Token counts in a sync-stable shape, independent of the app's `TokenCount`.
public struct LedgerTokens: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int
    public var reasoning: Int
    /// Subset of `cacheCreation` written with a one-hour TTL.
    public var cacheCreation1h: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        reasoning: Int = 0,
        cacheCreation1h: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.reasoning = reasoning
        self.cacheCreation1h = cacheCreation1h
    }

    public static let zero = LedgerTokens()

    public static func + (lhs: LedgerTokens, rhs: LedgerTokens) -> LedgerTokens {
        LedgerTokens(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            reasoning: lhs.reasoning + rhs.reasoning,
            cacheCreation1h: lhs.cacheCreation1h + rhs.cacheCreation1h
        )
    }
}

/// Tokens and estimated spend for one period.
public struct LedgerTotals: Codable, Equatable, Sendable {
    public var tokens: LedgerTokens
    public var costUSD: Double

    public init(tokens: LedgerTokens = .zero, costUSD: Double = 0) {
        self.tokens = tokens
        self.costUSD = costUSD
    }

    public static let zero = LedgerTotals()

    public static func + (lhs: LedgerTotals, rhs: LedgerTotals) -> LedgerTotals {
        LedgerTotals(tokens: lhs.tokens + rhs.tokens, costUSD: lhs.costUSD + rhs.costUSD)
    }
}

/// One provider's local usage on the publishing Mac, relative to `anchorDay`.
public struct ProviderLedger: Codable, Equatable, Sendable {
    public let provider: Provider
    /// False when the Mac only has effort data for this provider, so the token
    /// and cost fields are placeholders rather than genuine zero usage.
    public let hasTokenUsage: Bool
    public let today: LedgerTotals
    public let yesterday: LedgerTotals
    public let last30Days: LedgerTotals
    /// 30-day token totals per model.
    public let byModel: [String: LedgerTokens]
    /// Daily cost, oldest → newest, ending on the ledger's `anchorDay`.
    public let dailyCosts: [Double]
    /// Session effort distributions per period, as of `anchorDay`.
    public let effortSummaries: [EffortPeriodSummary]
    public let lastUsedAt: Date?

    public init(
        provider: Provider,
        hasTokenUsage: Bool = true,
        today: LedgerTotals,
        yesterday: LedgerTotals,
        last30Days: LedgerTotals,
        byModel: [String: LedgerTokens],
        dailyCosts: [Double],
        effortSummaries: [EffortPeriodSummary] = [],
        lastUsedAt: Date?
    ) {
        self.provider = provider
        self.hasTokenUsage = hasTokenUsage
        self.today = today
        self.yesterday = yesterday
        self.last30Days = last30Days
        self.byModel = byModel
        self.dailyCosts = dailyCosts
        self.effortSummaries = effortSummaries
        self.lastUsedAt = lastUsedAt
    }

    private enum CodingKeys: String, CodingKey {
        case provider, hasTokenUsage, today, yesterday, last30Days, byModel, dailyCosts
        case effortSummaries, lastUsedAt
    }

    /// Ledgers written before effort was shared carry token usage only.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(Provider.self, forKey: .provider)
        hasTokenUsage = try container.decodeIfPresent(Bool.self, forKey: .hasTokenUsage) ?? true
        today = try container.decode(LedgerTotals.self, forKey: .today)
        yesterday = try container.decode(LedgerTotals.self, forKey: .yesterday)
        last30Days = try container.decode(LedgerTotals.self, forKey: .last30Days)
        byModel = try container.decode([String: LedgerTokens].self, forKey: .byModel)
        dailyCosts = try container.decode([Double].self, forKey: .dailyCosts)
        effortSummaries = try container.decodeIfPresent(
            [EffortPeriodSummary].self,
            forKey: .effortSummaries
        ) ?? []
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}

/// Everything one Mac publishes about its own local token and cost usage.
public struct DeviceUsageLedger: Codable, Equatable, Identifiable, Sendable {
    /// Stable per-install identifier of the publishing Mac.
    public let deviceID: String
    /// User-facing computer name, e.g. "Studio".
    public let deviceName: String
    /// The publisher's calendar day that `today` refers to, as `yyyy-MM-dd`.
    public let anchorDay: String
    public let publishedAt: Date
    public let providers: [ProviderLedger]

    public var id: String { deviceID }

    public init(
        deviceID: String,
        deviceName: String,
        anchorDay: String,
        publishedAt: Date,
        providers: [ProviderLedger]
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.anchorDay = anchorDay
        self.publishedAt = publishedAt
        self.providers = providers
    }

    public func provider(_ provider: Provider) -> ProviderLedger? {
        providers.first { $0.provider == provider }
    }

    /// `yyyy-MM-dd` for the calendar day containing `date`.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// Whole days from `anchorDay` to the day containing `date`. Positive when
    /// the ledger was published on an earlier day. Nil for a malformed key.
    public static func dayOffset(
        from anchorDay: String,
        to date: Date,
        calendar: Calendar = .current
    ) -> Int? {
        let parts = anchorDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let anchor = calendar.date(from: components) else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor),
            to: calendar.startOfDay(for: date)
        ).day
    }
}
