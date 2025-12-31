//
//  TokenUsage.swift
//  ClaudeMeter
//

import Foundation

/// Pricing per million tokens (MTok) for Claude models
enum ModelPricing: Sendable {
    struct Rates: Sendable {
        let inputPerMTok: Double
        let outputPerMTok: Double
        let cacheWritePerMTok: Double
        let cacheReadPerMTok: Double
    }

    nonisolated static let opus45 = Rates(
        inputPerMTok: 5.0,
        outputPerMTok: 25.0,
        cacheWritePerMTok: 6.25,
        cacheReadPerMTok: 0.50
    )

    nonisolated static let sonnet45 = Rates(
        inputPerMTok: 3.0,
        outputPerMTok: 15.0,
        cacheWritePerMTok: 3.75,
        cacheReadPerMTok: 0.30
    )

    nonisolated static let sonnet4 = Rates(
        inputPerMTok: 3.0,
        outputPerMTok: 15.0,
        cacheWritePerMTok: 3.75,
        cacheReadPerMTok: 0.30
    )

    nonisolated static let haiku45 = Rates(
        inputPerMTok: 1.0,
        outputPerMTok: 5.0,
        cacheWritePerMTok: 1.25,
        cacheReadPerMTok: 0.10
    )

    nonisolated static let haiku35 = Rates(
        inputPerMTok: 0.80,
        outputPerMTok: 4.0,
        cacheWritePerMTok: 1.0,
        cacheReadPerMTok: 0.08
    )

    /// Get pricing rates for a model name
    nonisolated static func rates(for model: String) -> Rates? {
        let lowercased = model.lowercased()

        if lowercased.contains("opus-4-5") || lowercased.contains("opus-4.5") {
            return opus45
        } else if lowercased.contains("sonnet-4-5") || lowercased.contains("sonnet-4.5") {
            return sonnet45
        } else if lowercased.contains("sonnet-4") {
            return sonnet4
        } else if lowercased.contains("haiku-4-5") || lowercased.contains("haiku-4.5") {
            return haiku45
        } else if lowercased.contains("haiku-3-5") || lowercased.contains("haiku-3.5") || lowercased.contains("haiku") {
            return haiku35
        }

        return nil
    }
}

/// Token counts from a single API request
struct TokenCount: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    nonisolated static let zero = TokenCount(inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0)
}

nonisolated func + (lhs: TokenCount, rhs: TokenCount) -> TokenCount {
    TokenCount(
        inputTokens: lhs.inputTokens + rhs.inputTokens,
        outputTokens: lhs.outputTokens + rhs.outputTokens,
        cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
        cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens
    )
}

/// Usage entry parsed from JSONL log
struct UsageEntry: Sendable {
    let model: String
    let tokens: TokenCount
    let timestamp: Date
}

/// Aggregated token usage with cost calculation
struct TokenUsageSummary: Sendable {
    let tokens: TokenCount
    let costUSD: Double
    let period: UsagePeriod

    enum UsagePeriod: Sendable {
        case today
        case last30Days
    }

    var formattedCost: String {
        String(format: "$%.2f", costUSD)
    }

    var formattedTokens: String {
        formatTokenCount(tokens.totalTokens)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// Complete token usage snapshot
struct TokenUsageSnapshot: Sendable {
    let today: TokenUsageSummary
    let last30Days: TokenUsageSummary
    let byModel: [String: TokenCount]
    let fetchedAt: Date
}
