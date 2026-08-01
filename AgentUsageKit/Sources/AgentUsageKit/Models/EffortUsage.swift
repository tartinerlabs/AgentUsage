//
//  EffortUsage.swift
//  AgentUsageKit
//
//  Shared models for session effort-level usage.
//

import Foundation

/// A configured reasoning effort level found in a provider session log.
///
/// This is a string-backed value instead of an enum so newer provider-defined
/// levels remain readable by older versions of AgentUsage.
public struct EffortLevel: RawRepresentable, Hashable, Codable, Sendable, Comparable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let minimal = Self(rawValue: "minimal")
    public static let low = Self(rawValue: "low")
    public static let medium = Self(rawValue: "medium")
    public static let high = Self(rawValue: "high")
    public static let xhigh = Self(rawValue: "xhigh")
    public static let max = Self(rawValue: "max")
    public static let ultra = Self(rawValue: "ultra")
    public static let mixed = Self(rawValue: "mixed")

    /// Known levels in their preferred presentation order.
    public static let displayOrder: [Self] = [
        .minimal,
        .low,
        .medium,
        .high,
        .xhigh,
        .max,
        .ultra,
        .mixed,
    ]

    public var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "X-High"
        case .max: "Max"
        case .ultra: "Ultra"
        case .mixed: "Mixed"
        default: rawValue
        }
    }

    /// Stable presentation rank. Unknown future levels sort after known concrete
    /// levels but before the aggregate `mixed` value.
    public var sortOrder: Int {
        switch self {
        case .minimal: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        case .xhigh: 4
        case .max: 5
        case .ultra: 6
        case .mixed: 8
        default: 7
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsRank = lhs.sortOrder
        let rhsRank = rhs.sortOrder
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

}

/// A time range for effort-level session aggregation.
public enum EffortPeriod: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case today
    case last7Days
    case last30Days
    case last90Days
    case last180Days
    case lastYear

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "Today"
        case .last7Days: "7 Days"
        case .last30Days: "30 Days"
        case .last90Days: "90 Days"
        case .last180Days: "180 Days"
        case .lastYear: "Year"
        }
    }
}

/// Number of sessions assigned to an effort level.
public struct EffortLevelCount: Sendable, Codable, Hashable {
    public let level: EffortLevel
    public let sessionCount: Int

    public init(level: EffortLevel, sessionCount: Int) {
        self.level = level
        self.sessionCount = sessionCount
    }
}

/// Effort-level distribution and classification coverage for one time period.
public struct EffortPeriodSummary: Sendable, Codable, Hashable {
    public let period: EffortPeriod
    public let levels: [EffortLevelCount]
    public let classifiedSessionCount: Int
    public let unclassifiedSessionCount: Int

    public init(
        period: EffortPeriod,
        levels: [EffortLevelCount],
        classifiedSessionCount: Int,
        unclassifiedSessionCount: Int
    ) {
        self.period = period
        self.levels = levels
        self.classifiedSessionCount = classifiedSessionCount
        self.unclassifiedSessionCount = unclassifiedSessionCount
    }

    public var totalSessionCount: Int {
        classifiedSessionCount + unclassifiedSessionCount
    }

    public func levelCount(for level: EffortLevel) -> EffortLevelCount? {
        levels.first { $0.level == level }
    }

    public func sessionCount(for level: EffortLevel) -> Int {
        levels.lazy
            .filter { $0.level == level }
            .reduce(0) { $0 + $1.sessionCount }
    }

    /// Share of classified sessions assigned to `level`, expressed from 0 through 1.
    public func fraction(for level: EffortLevel) -> Double {
        guard classifiedSessionCount > 0 else { return 0 }
        return Double(sessionCount(for: level)) / Double(classifiedSessionCount)
    }
}
