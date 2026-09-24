//
//  UsageData.swift
//  AgentUsageKit
//
//  Shared models for usage data across app and extensions
//

import Foundation
import SwiftUI

// MARK: - Usage Status

public enum UsageStatus: String, Sendable, Codable, Comparable {
    case onTrack
    case warning
    case critical

    public var label: String {
        switch self {
        case .onTrack: "Low"
        case .warning: "Moderate"
        case .critical: "High"
        }
    }

    public var icon: String {
        switch self {
        case .onTrack: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .onTrack: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.severity < rhs.severity
    }

    /// `critical > warning > onTrack`, matching `UsageCalculations.overallStatus`.
    private var severity: Int {
        switch self {
        case .onTrack: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

// MARK: - Usage Window Type

public enum UsageWindowType: String, Sendable, Codable {
    case session  // 5 hours (five_hour)
    case opus     // 7 days - default weekly limit (seven_day)
    case sonnet   // 7 days - separate Sonnet limit (seven_day_sonnet)
    case design   // 7 days - Claude Design limit (seven_day_omelette)
    case fable    // 7 days - separate Fable limit (limits[] weekly_scoped, scope.model.display_name == "Fable")

    // Generic windows for providers other than Claude.
    case codexFiveHour  // Codex primary limit (rate_limits.primary, window_minutes 300)
    case codexWeekly    // Codex secondary limit (rate_limits.secondary, window_minutes 10080)
    case openCodeGoFiveHour
    case openCodeGoWeekly
    case openCodeGoMonthly
    /// SuperGrok unified weekly credit pool (`creditUsagePercent`).
    case grokWeekly
    /// Compatibility value for provider-defined windows unknown to older clients.
    case custom

    public var displayName: String {
        switch self {
        case .session: "Current session"
        case .opus: "All models"
        case .sonnet: "Sonnet"
        case .design: "Claude Design"
        case .fable: "Fable"
        case .codexFiveHour: "5-hour limit"
        case .codexWeekly: "Weekly limit"
        case .openCodeGoFiveHour: "Rolling Usage"
        case .openCodeGoWeekly: "Weekly Usage"
        case .openCodeGoMonthly: "Monthly Usage"
        case .grokWeekly: "Weekly limit"
        case .custom: "Usage"
        }
    }

    public var totalDuration: TimeInterval {
        switch self {
        case .session: 5 * 60 * 60      // 5 hours in seconds
        case .opus: 7 * 24 * 60 * 60    // 7 days in seconds
        case .sonnet: 7 * 24 * 60 * 60  // 7 days in seconds
        case .design: 7 * 24 * 60 * 60  // 7 days in seconds
        case .fable: 7 * 24 * 60 * 60   // 7 days in seconds
        case .codexFiveHour: 5 * 60 * 60      // 5 hours in seconds
        case .codexWeekly: 7 * 24 * 60 * 60   // 7 days in seconds
        case .openCodeGoFiveHour: 5 * 60 * 60
        case .openCodeGoWeekly: 7 * 24 * 60 * 60
        case .openCodeGoMonthly: 30 * 24 * 60 * 60
        case .grokWeekly: 7 * 24 * 60 * 60
        case .custom: 0
        }
    }
}

/// Stable, provider-defined identifier for a rate-limit window.
public struct UsageWindowID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// Optional scope metadata for provider-defined windows.
public struct UsageWindowScope: Hashable, Codable, Sendable {
    public let model: String?

    public init(model: String? = nil) {
        self.model = model
    }
}

// MARK: - Usage Window

public struct UsageWindow: Sendable, Codable, Identifiable {
    public let utilization: Double  // API returns percentage (0-100), not decimal (0-1)
    public let resetsAt: Date
    public let windowID: UsageWindowID
    public let displayName: String
    public let totalDuration: TimeInterval
    public let scope: UsageWindowScope?
    /// Legacy compatibility for existing menu-pin and notification code.
    public let windowType: UsageWindowType
    /// Dollar budget behind this window (e.g. a Claude usage credit), when the provider reports one.
    public let budget: ExtraUsageCost?
    /// A one-time allowance that expires at `resetsAt` instead of renewing.
    public let isOneTime: Bool
    /// The provider's own grading of this window (Claude `limits[].severity`).
    /// It floors the local pace-based status rather than replacing it.
    public let serverStatus: UsageStatus?
    /// Why the provider has locked this window, when it has (Claude `locked_reason`).
    public let lockedReason: String?

    /// Stable per-provider identity. Providers may reorder windows between
    /// fetches (Codex moves its weekly limit into the primary slot while the
    /// five-hour limit is unavailable), so views must not identify by position.
    public var id: UsageWindowID { windowID }

    public init(utilization: Double, resetsAt: Date, windowType: UsageWindowType) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.windowID = UsageWindowID(rawValue: windowType.rawValue)
        self.displayName = windowType.displayName
        self.totalDuration = windowType.totalDuration
        self.scope = nil
        self.windowType = windowType
        self.budget = nil
        self.isOneTime = false
        self.serverStatus = nil
        self.lockedReason = nil
    }

    /// Returns a copy carrying provider-reported extras on top of this window.
    public func with(
        budget: ExtraUsageCost? = nil,
        serverStatus: UsageStatus? = nil,
        lockedReason: String? = nil
    ) -> UsageWindow {
        UsageWindow(
            utilization: utilization,
            resetsAt: resetsAt,
            windowID: windowID,
            displayName: displayName,
            totalDuration: totalDuration,
            scope: scope,
            budget: budget ?? self.budget,
            isOneTime: isOneTime,
            serverStatus: serverStatus ?? self.serverStatus,
            lockedReason: lockedReason ?? self.lockedReason
        )
    }

    public init(
        utilization: Double,
        resetsAt: Date,
        windowID: UsageWindowID,
        displayName: String,
        totalDuration: TimeInterval,
        scope: UsageWindowScope? = nil,
        budget: ExtraUsageCost? = nil,
        isOneTime: Bool = false,
        serverStatus: UsageStatus? = nil,
        lockedReason: String? = nil
    ) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.windowID = windowID
        self.displayName = displayName
        self.totalDuration = max(0, totalDuration)
        self.scope = scope
        self.windowType = UsageWindowType(rawValue: windowID.rawValue) ?? .custom
        self.budget = budget
        self.isOneTime = isOneTime
        self.serverStatus = serverStatus
        self.lockedReason = lockedReason
    }

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt
        case windowID
        case displayName
        case totalDuration
        case scope
        case windowType
        case budget
        case isOneTime
        case serverStatus
        case lockedReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try container.decode(Double.self, forKey: .utilization)
        resetsAt = try container.decode(Date.self, forKey: .resetsAt)
        let legacy = try container.decodeIfPresent(UsageWindowType.self, forKey: .windowType)
        let decodedID = try container.decodeIfPresent(UsageWindowID.self, forKey: .windowID)
        let resolvedID = decodedID ?? UsageWindowID(rawValue: legacy?.rawValue ?? UsageWindowType.custom.rawValue)
        windowID = resolvedID
        windowType = legacy ?? UsageWindowType(rawValue: resolvedID.rawValue) ?? .custom
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? windowType.displayName
        totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration)
            ?? windowType.totalDuration
        scope = try container.decodeIfPresent(UsageWindowScope.self, forKey: .scope)
        budget = try container.decodeIfPresent(ExtraUsageCost.self, forKey: .budget)
        isOneTime = try container.decodeIfPresent(Bool.self, forKey: .isOneTime) ?? false
        serverStatus = try container.decodeIfPresent(UsageStatus.self, forKey: .serverStatus)
        lockedReason = try container.decodeIfPresent(String.self, forKey: .lockedReason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(utilization, forKey: .utilization)
        try container.encode(resetsAt, forKey: .resetsAt)
        try container.encode(windowID, forKey: .windowID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(totalDuration, forKey: .totalDuration)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encode(windowType, forKey: .windowType)
        try container.encodeIfPresent(budget, forKey: .budget)
        if isOneTime { try container.encode(isOneTime, forKey: .isOneTime) }
        try container.encodeIfPresent(serverStatus, forKey: .serverStatus)
        try container.encodeIfPresent(lockedReason, forKey: .lockedReason)
    }

    public var percentUsed: Int {
        Int(utilization)
    }

    public var isAtLimit: Bool {
        utilization >= 100
    }

    /// Whether this window's reset time has passed. A stale cached window whose
    /// reset has elapsed no longer reflects live usage (its percentage is from the
    /// previous, now-reset period), so callers can render it as awaiting a new period
    /// instead of showing the old percentage.
    public var isExpired: Bool {
        isExpired(from: Date())
    }

    public func isExpired(from now: Date) -> Bool {
        resetsAt < now
    }

    /// Whether this window is in extra usage territory (billed at API rates)
    public var isUsingExtraUsage: Bool {
        utilization > 100
    }

    /// Percentage of usage beyond the plan limit (e.g., 115% → 15%)
    public var extraUsagePercent: Int {
        max(0, Int(utilization) - 100)
    }

    public var normalized: Double {
        min(max(utilization / 100.0, 0), 1)  // Clamped 0-1 for Gauge/ProgressView
    }

    public var timeUntilReset: String {
        timeUntilReset(from: Date())
    }

    public func timeUntilReset(from now: Date) -> String {
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Full user-facing reset phrase.
    ///
    /// `timeUntilReset` returns the bare word "now" for an elapsed window, which reads
    /// as "Resets in now" when callers prefix it. Use this wherever the countdown is
    /// presented as a sentence.
    public func resetDescription(from now: Date = Date()) -> String {
        let verb = isOneTime ? "Expires" : "Resets"
        if !hasResetDate { return isOneTime ? "No expiry" : "No reset date" }
        return resetsAt <= now ? "\(verb) now" : "\(verb) in \(timeUntilReset(from: now))"
    }

    /// False when the provider reported no reset/expiry time (stored as `.distantFuture`).
    public var hasResetDate: Bool {
        resetsAt < .distantFuture
    }

    /// Calculate usage status based on absolute usage and consumption rate
    public var status: UsageStatus {
        status(from: Date())
    }

    /// Status as of an explicit moment.
    ///
    /// WidgetKit renders every entry of a timeline at the moment the timeline is
    /// built, so `Date()` inside a widget view body is identical for all entries.
    /// Widgets must pass their entry's date here for a multi-entry timeline to
    /// advance the pace-based status over time.
    public func status(from now: Date) -> UsageStatus {
        guard resetsAt.timeIntervalSince(now) > 0 else { return .onTrack }
        return max(paceStatus(from: now), serverStatus ?? .onTrack)
    }

    private func paceStatus(from now: Date) -> UsageStatus {
        let timeRemaining = resetsAt.timeIntervalSince(now)

        // Check absolute usage first - high usage is always concerning
        if utilization >= 90 {
            return .critical
        } else if utilization >= 75 {
            return .warning
        }

        // Then check pace relative to time elapsed
        guard totalDuration > 0 else { return .onTrack }
        let timeElapsed = totalDuration - timeRemaining
        let timeElapsedRatio = timeElapsed / totalDuration

        // Expected usage if consuming evenly over the window
        let expectedUsage = timeElapsedRatio * 100

        // How much ahead/behind schedule
        let difference = utilization - expectedUsage

        // Thresholds: within 10% is on track, within 25% is warning
        if difference <= 10 {
            return .onTrack
        } else if difference <= 25 {
            return .warning
        } else {
            return .critical
        }
    }

    /// Trend indicator based on current pace vs expected pace
    public enum Trend: String, Sendable {
        case increasing  // Using faster than expected
        case stable      // On pace
        case decreasing  // Using slower than expected

        public var icon: String {
            switch self {
            case .increasing: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .decreasing: return "arrow.down.right"
            }
        }

        public var accessibilityLabel: String {
            switch self {
            case .increasing: return "increasing"
            case .stable: return "stable"
            case .decreasing: return "decreasing"
            }
        }

        /// System-semantic color paired with the trend arrow in every surface.
        public var color: Color {
            switch self {
            case .increasing: return .orange
            case .stable: return .secondary
            case .decreasing: return .green
            }
        }
    }

    /// Calculate trend based on current usage pace
    public var trend: Trend {
        trend(from: Date())
    }

    /// Trend as of an explicit moment. See `status(from:)` for why widgets need this.
    public func trend(from now: Date) -> Trend {
        let timeRemaining = resetsAt.timeIntervalSince(now)
        guard timeRemaining > 0 else { return .stable }

        guard totalDuration > 0 else { return .stable }
        let timeElapsed = totalDuration - timeRemaining
        guard timeElapsed > 0 else { return .stable }

        let timeElapsedRatio = timeElapsed / totalDuration
        let expectedUsage = timeElapsedRatio * 100
        let difference = utilization - expectedUsage

        if difference > 10 {
            return .increasing
        } else if difference < -10 {
            return .decreasing
        } else {
            return .stable
        }
    }
}

// MARK: - Extra Usage Cost

/// Monthly extra usage spending data (billed at API rates beyond plan limits)
public struct ExtraUsageCost: Sendable, Codable {
    /// Amount spent in major currency units (e.g., dollars)
    public let used: Double
    /// Monthly spending limit in major currency units
    public let limit: Double
    /// Currency code (e.g., "USD")
    public let currencyCode: String

    public init(used: Double, limit: Double, currencyCode: String) {
        self.used = used
        self.limit = limit
        self.currencyCode = currencyCode
    }

    /// Percentage of spending limit used (0-100+)
    public var percentUsed: Double {
        guard limit > 0 else { return 0 }
        return (used / limit) * 100
    }

    /// Normalized value clamped 0-1 for progress bars
    public var normalized: Double {
        min(max(percentUsed / 100.0, 0), 1)
    }

    /// Formatted used amount (e.g., "$1.23")
    public var formattedUsed: String {
        Self.formatCurrency(used, code: currencyCode)
    }

    /// Formatted limit amount (e.g., "$50.00")
    public var formattedLimit: String {
        Self.formatCurrency(limit, code: currencyCode)
    }

    private static func formatCurrency(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// MARK: - Usage Share

/// One row of a provider's usage split, e.g. Claude's `seven_day_breakdown`
/// ("Claude Code 80%, Chats 20%").
public struct UsageShare: Sendable, Codable, Equatable, Identifiable {
    public let key: String
    public let displayName: String
    /// Share of the period's usage, 0-100.
    public let percent: Double

    public var id: String { key }

    public init(key: String, displayName: String, percent: Double) {
        self.key = key
        self.displayName = displayName
        self.percent = percent
    }
}

// MARK: - Usage Snapshot

public struct UsageSnapshot: Sendable, Codable {
    public let session: UsageWindow
    public let opus: UsageWindow      // Weekly default limit (was "seven_day")
    public let sonnet: UsageWindow?   // Separate Sonnet limit (if available)
    public let design: UsageWindow?   // Claude Design limit (if available)
    public let fable: UsageWindow?    // Separate Fable limit (if available)
    public let extraUsage: ExtraUsageCost?  // Monthly extra usage spending
    public let rateLimitResetCredits: RateLimitResetCredits?  // Banked "reset your limits" grants
    /// Every other window the endpoint reports (scoped `limits[]` rows, Opus/Cowork/OAuth-app
    /// weeks, usage credits), in server order.
    public let additionalWindows: [UsageWindow]
    /// This week's usage split by surface (`seven_day_breakdown`), in server order.
    public let weeklyBreakdown: [UsageShare]
    public let fetchedAt: Date

    public init(session: UsageWindow, opus: UsageWindow, sonnet: UsageWindow?, design: UsageWindow? = nil, fable: UsageWindow? = nil, extraUsage: ExtraUsageCost? = nil, rateLimitResetCredits: RateLimitResetCredits? = nil, additionalWindows: [UsageWindow] = [], weeklyBreakdown: [UsageShare] = [], fetchedAt: Date) {
        self.session = session
        self.opus = opus
        self.sonnet = sonnet
        self.design = design
        self.fable = fable
        self.extraUsage = extraUsage
        self.rateLimitResetCredits = rateLimitResetCredits
        self.additionalWindows = additionalWindows
        self.weeklyBreakdown = weeklyBreakdown
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(UsageWindow.self, forKey: .session)
        opus = try container.decode(UsageWindow.self, forKey: .opus)
        sonnet = try container.decodeIfPresent(UsageWindow.self, forKey: .sonnet)
        design = try container.decodeIfPresent(UsageWindow.self, forKey: .design)
        fable = try container.decodeIfPresent(UsageWindow.self, forKey: .fable)
        extraUsage = try container.decodeIfPresent(ExtraUsageCost.self, forKey: .extraUsage)
        rateLimitResetCredits = try container.decodeIfPresent(RateLimitResetCredits.self, forKey: .rateLimitResetCredits)
        additionalWindows = try container.decodeIfPresent([UsageWindow].self, forKey: .additionalWindows) ?? []
        weeklyBreakdown = try container.decodeIfPresent([UsageShare].self, forKey: .weeklyBreakdown) ?? []
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
    }

    /// Every window in display order: the fixed Claude windows, then `additionalWindows`.
    public var allWindows: [UsageWindow] {
        [session, opus, sonnet, design, fable].compactMap { $0 } + additionalWindows
    }

    /// Whether any window is currently in extra usage territory
    public var isExtraUsageActive: Bool {
        session.isUsingExtraUsage || opus.isUsingExtraUsage || (sonnet?.isUsingExtraUsage ?? false) || (design?.isUsingExtraUsage ?? false) || (fable?.isUsingExtraUsage ?? false)
    }

    /// True when every window's reset time has passed. Used as a safety net in
    /// `refreshClaude()`: if a fetch fails and the cached snapshot's windows
    /// are all expired, the cached data is stale (from before a reset) and is
    /// dropped in favor of a "No usage data" state.
    public var allWindowsExpired: Bool {
        let now = Date()
        // One-time credits can outlive every rate window, so they don't keep a stale snapshot alive.
        let rateWindows = allWindows.filter { !$0.isOneTime }
        guard !rateWindows.isEmpty else { return true }
        return rateWindows.allSatisfy { $0.isExpired(from: now) }
    }

    /// Whether extra usage is enabled (has cost data from the API)
    public var hasExtraUsageEnabled: Bool {
        extraUsage != nil
    }

    public var lastUpdatedDescription: String {
        lastUpdatedDescription(asOf: Date())
    }

    /// Relative age as of an explicit moment. See `UsageWindow.status(from:)` for
    /// why widgets must pass their entry's date rather than rely on `Date()`.
    public func lastUpdatedDescription(asOf now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fetchedAt, relativeTo: now)
    }

    /// Seconds between this snapshot's fetch and `now`.
    public func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}

// MARK: - Rate Limit Reset Credits

/// On-demand rate-limit reset credits for a Codex or Claude account.
///
/// Codex: the count comes from the usage body's `rate_limit_reset_credits.available_count`
/// (always available) or the dedicated `/wham/rate-limit-reset-credits` endpoint
/// (which also carries each credit's expiry). When only the count is available,
/// `expirations` is empty.
///
/// Claude: banked "reset your limits" grants from the usage body's `cedar_ember`
/// block, one credit per `resets_left`, each expiring at its grant's `ends_at`.
public struct RateLimitResetCredits: Sendable, Codable, Equatable {
    /// Number of reset credits still available (floored).
    public let availableCount: Int
    /// Per-credit expiry dates for still-available credits, sorted soonest-first.
    /// Empty when only the usage-body count was available (no dedicated fetch).
    public let expirations: [Date]
    /// Claude grant labels (e.g. "Claude Opus 5.5 launch: one usage-limit reset…"), one per live grant.
    public let grantLabels: [String]
    /// Claude `cooldown_until`: a banked reset can't be used again before this time.
    public let cooldownUntil: Date?

    public init(availableCount: Int, expirations: [Date] = [], grantLabels: [String] = [], cooldownUntil: Date? = nil) {
        self.availableCount = availableCount
        self.expirations = expirations
        self.grantLabels = grantLabels
        self.cooldownUntil = cooldownUntil
    }

    private enum CodingKeys: String, CodingKey {
        case availableCount
        case expirations
        case grantLabels
        case cooldownUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableCount = try container.decode(Int.self, forKey: .availableCount)
        expirations = try container.decodeIfPresent([Date].self, forKey: .expirations) ?? []
        grantLabels = try container.decodeIfPresent([String].self, forKey: .grantLabels) ?? []
        cooldownUntil = try container.decodeIfPresent(Date.self, forKey: .cooldownUntil)
    }

    /// The soonest expiry, if any — drives the 24-hour warning triangle.
    public var soonestExpiration: Date? {
        expirations.min()
    }

    /// True when the soonest still-available credit expires within 24 hours
    /// (or is already past due). Drives the amber warning triangle in the UI.
    public func hasImminentExpiry(now: Date = Date()) -> Bool {
        guard let soonest = soonestExpiration else { return false }
        return soonest.timeIntervalSince(now) <= 24 * 60 * 60
    }

    /// Hover-tooltip text listing each credit's expiry countdown.
    /// Returns nil when there are no per-credit expiry dates (count-only fallback).
    public func tooltipText(now: Date = Date()) -> String? {
        var lines = grantLabels
        if let cooldownUntil, cooldownUntil > now {
            lines.append("Next reset usable in \(Self.countdownLabel(cooldownUntil, from: now))")
        }
        let sorted = expirations.sorted()
        if sorted.count == 1 {
            lines.append("Reset expires in \(Self.countdownLabel(sorted[0], from: now))")
        } else if !sorted.isEmpty {
            lines.append("Resets expire in:")
            lines += sorted.enumerated().map { index, date in
                "\(index + 1). \(Self.countdownLabel(date, from: now))"
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func countdownLabel(_ date: Date, from now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "soon" }
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// MARK: - Credit Balance

/// Spendable usage credits a provider reports next to its rate windows (Codex
/// `credits` on `/wham/usage`). Unrelated to `RateLimitResetCredits`, which counts
/// banked limit resets rather than a balance to spend.
public struct CreditBalance: Sendable, Codable, Equatable {
    /// Credits left to spend. nil when `isUnlimited`.
    public let remaining: Double?
    /// The account's credits are unlimited.
    public let isUnlimited: Bool

    public static let unlimited = CreditBalance(remaining: nil, isUnlimited: true)

    public init(remaining: Double) {
        self.init(remaining: remaining, isUnlimited: false)
    }

    private init(remaining: Double?, isUnlimited: Bool) {
        self.remaining = remaining
        self.isUnlimited = isUnlimited
    }

    private enum CodingKeys: String, CodingKey {
        case remaining
        case isUnlimited
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
        isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? false
    }

    /// Card value: "Unlimited", or the balance, e.g. "1,250 available".
    /// nil when there is no balance to show.
    public var displayValue: String? {
        if isUnlimited { return "Unlimited" }
        guard let remaining, remaining.isFinite else { return nil }
        return "\(remaining.formatted(.number.precision(.fractionLength(0...2)))) available"
    }
}

// MARK: - Provider Usage Snapshot

/// Provider-agnostic rate-window snapshot.
///
/// Unlike `UsageSnapshot` (which has fixed Claude-shaped fields), this holds an
/// ordered list of windows so providers with a different number/kind of windows
/// (e.g. Codex's 5-hour + weekly) can be represented uniformly.
public struct ProviderUsageSnapshot: Sendable, Codable, Identifiable {
    public let provider: Provider
    public let windows: [UsageWindow]
    public let extraUsage: ExtraUsageCost?
    /// Plan / tier name reported by the provider, if any (e.g. Codex `plan_type`).
    public let planName: String?
    /// On-demand rate-limit reset credits (Codex and Claude). nil when the provider
    /// doesn't report them or the account has no reset-credit balance.
    public let rateLimitResetCredits: RateLimitResetCredits?
    /// Spendable credits (Codex `credits`). nil when the provider doesn't report
    /// them or the account has none to spend.
    public let creditBalance: CreditBalance?
    /// Session effort distributions, grouped by aggregation period.
    public let effortSummaries: [EffortPeriodSummary]
    /// The provider's usage split for the current period (Claude: by surface this week).
    public let usageBreakdown: [UsageShare]
    public let fetchedAt: Date
    /// Newest local session or token-log timestamp. Nil when the provider has
    /// quota data but no local activity we can date (for example Cursor).
    public let lastUsedAt: Date?

    public var id: String { provider.id }

    public init(
        provider: Provider,
        windows: [UsageWindow],
        extraUsage: ExtraUsageCost? = nil,
        planName: String? = nil,
        rateLimitResetCredits: RateLimitResetCredits? = nil,
        creditBalance: CreditBalance? = nil,
        effortSummaries: [EffortPeriodSummary] = [],
        usageBreakdown: [UsageShare] = [],
        fetchedAt: Date,
        lastUsedAt: Date? = nil
    ) {
        self.provider = provider
        self.windows = windows
        self.extraUsage = extraUsage
        self.planName = planName
        self.rateLimitResetCredits = rateLimitResetCredits
        self.creditBalance = creditBalance
        self.effortSummaries = effortSummaries
        self.usageBreakdown = usageBreakdown
        self.fetchedAt = fetchedAt
        self.lastUsedAt = lastUsedAt
    }

    /// Bridge an existing Claude `UsageSnapshot` into the provider-agnostic shape.
    public init(
        claude snapshot: UsageSnapshot,
        planName: String? = nil,
        effortSummaries: [EffortPeriodSummary] = [],
        lastUsedAt: Date? = nil
    ) {
        self.provider = .claude
        self.windows = snapshot.allWindows
        self.extraUsage = snapshot.extraUsage
        self.planName = planName
        self.rateLimitResetCredits = snapshot.rateLimitResetCredits
        self.creditBalance = nil
        self.effortSummaries = effortSummaries
        self.usageBreakdown = snapshot.weeklyBreakdown
        self.fetchedAt = snapshot.fetchedAt
        self.lastUsedAt = lastUsedAt
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case windows
        case extraUsage
        case planName
        case rateLimitResetCredits
        case creditBalance
        case effortSummaries
        case usageBreakdown
        case fetchedAt
        case lastUsedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(Provider.self, forKey: .provider)
        windows = try container.decode([UsageWindow].self, forKey: .windows)
        extraUsage = try container.decodeIfPresent(ExtraUsageCost.self, forKey: .extraUsage)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        rateLimitResetCredits = try container.decodeIfPresent(
            RateLimitResetCredits.self,
            forKey: .rateLimitResetCredits
        )
        creditBalance = try container.decodeIfPresent(CreditBalance.self, forKey: .creditBalance)
        effortSummaries = try container.decodeIfPresent(
            [EffortPeriodSummary].self,
            forKey: .effortSummaries
        ) ?? []
        usageBreakdown = try container.decodeIfPresent([UsageShare].self, forKey: .usageBreakdown) ?? []
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(windows, forKey: .windows)
        try container.encodeIfPresent(extraUsage, forKey: .extraUsage)
        try container.encodeIfPresent(planName, forKey: .planName)
        try container.encodeIfPresent(rateLimitResetCredits, forKey: .rateLimitResetCredits)
        try container.encodeIfPresent(creditBalance, forKey: .creditBalance)
        try container.encode(effortSummaries, forKey: .effortSummaries)
        if !usageBreakdown.isEmpty { try container.encode(usageBreakdown, forKey: .usageBreakdown) }
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }

    public func effortSummary(for period: EffortPeriod) -> EffortPeriodSummary? {
        effortSummaries.first { $0.period == period }
    }

    /// Worst (highest-utilization) window, useful for compact status indicators.
    public var worstWindow: UsageWindow? {
        windows.max { $0.utilization < $1.utilization }
    }
}
