//
//  WrappedSummary.swift
//  AgentUsage
//

#if os(iOS)
import Foundation

/// A year-in-review summary of Claude Code usage for the "Claude Wrapped" tab.
///
/// Values are currently supplied by ``mock`` while the CloudKit sync core
/// (GitHub #8) is built out. The shape mirrors what a real aggregation over
/// persisted `TokenLogEntry` rows would produce — yearly totals, a by-model
/// breakdown, and per-month buckets — so the view can be pointed at live data
/// later without any UI changes.
struct WrappedSummary: Equatable {
    struct ModelShare: Identifiable, Equatable {
        /// Model name; stable identity for `ForEach`.
        let id: String
        let modelName: String
        let tokens: Int
        let costUSD: Double
        /// Fraction of the year's total tokens, 0...1.
        let fraction: Double
    }

    struct MonthPoint: Identifiable, Equatable {
        var id: Int { month }
        /// 1...12.
        let month: Int
        let tokens: Int
    }

    let year: Int
    let totalTokens: Int
    let totalCostUSD: Double
    let activeDays: Int
    let longestStreakDays: Int
    let busiestDay: Date
    let busiestDayTokens: Int
    let cacheReadTokens: Int
    let cacheSavingsUSD: Double
    /// Fraction of requests made in fast mode, 0...1.
    let fastModeFraction: Double
    /// Sorted descending by tokens.
    let modelShares: [ModelShare]
    /// Exactly 12 entries, January...December.
    let monthlyTokens: [MonthPoint]

    var topModel: ModelShare? { modelShares.first }
    var busiestMonth: MonthPoint? { monthlyTokens.max { $0.tokens < $1.tokens } }
    var peakMonthlyTokens: Int { monthlyTokens.map(\.tokens).max() ?? 0 }
}

extension WrappedSummary {
    /// Deterministic, realistic sample data for a heavy Claude Code year.
    ///
    /// Replace with a real aggregation over persisted `TokenLogEntry` rows once
    /// iOS retains a full year of usage (see the GitHub #8 CloudKit sync core).
    static let mock: WrappedSummary = {
        let year = 2026

        // (name, tokens, costUSD) — fractions are derived so they always agree.
        let rawShares: [(name: String, tokens: Int, cost: Double)] = [
            ("Claude Opus 4.8", 1_320_000_000, 980.40),
            ("Claude Sonnet 4.5", 720_000_000, 178.20),
            ("Claude Haiku 4.5", 300_000_000, 22.10),
            ("Claude Fable 5", 60_000_000, 8.30),
        ]
        let totalTokens = rawShares.reduce(0) { $0 + $1.tokens }
        let modelShares = rawShares.map { entry in
            ModelShare(
                id: entry.name,
                modelName: entry.name,
                tokens: entry.tokens,
                costUSD: entry.cost,
                fraction: totalTokens > 0 ? Double(entry.tokens) / Double(totalTokens) : 0
            )
        }

        // Millions of tokens per calendar month, peaking in March.
        let monthlyMillions = [120, 150, 340, 210, 190, 175, 165, 180, 200, 230, 220, 220]
        let monthlyTokens = monthlyMillions.enumerated().map { index, millions in
            MonthPoint(month: index + 1, tokens: millions * 1_000_000)
        }

        var busiest = DateComponents()
        busiest.year = year
        busiest.month = 3
        busiest.day = 18
        let busiestDay = Calendar(identifier: .gregorian).date(from: busiest)
            ?? Date(timeIntervalSince1970: 0)

        return WrappedSummary(
            year: year,
            totalTokens: totalTokens,
            totalCostUSD: rawShares.reduce(0) { $0 + $1.cost },
            activeDays: 287,
            longestStreakDays: 34,
            busiestDay: busiestDay,
            busiestDayTokens: 28_500_000,
            cacheReadTokens: 1_650_000_000,
            cacheSavingsUSD: 3_820.00,
            fastModeFraction: 0.18,
            modelShares: modelShares,
            monthlyTokens: monthlyTokens
        )
    }()
}

/// Compact formatting helpers for Wrapped figures.
enum WrappedFormat {
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(count)"
    }

    static func cost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func monthAbbrev(_ month: Int) -> String {
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard month >= 1, month <= symbols.count else { return "\(month)" }
        return symbols[month - 1]
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day())
    }
}
#endif
