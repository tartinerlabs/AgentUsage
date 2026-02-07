//
//  TokenUsage.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit

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

        if lowercased.contains("opus-4-6") || lowercased.contains("opus-4.6") {
            return opus45
        } else if lowercased.contains("opus-4-5") || lowercased.contains("opus-4.5") {
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

/// Time periods for usage aggregation
enum UsagePeriod: String, Sendable, CaseIterable, Identifiable {
    case today = "Today"
    case last7Days = "7 Days"
    case last30Days = "30 Days"
    case last90Days = "90 Days"
    case last180Days = "180 Days"
    case lastYear = "Year"

    var id: String { rawValue }

    /// Start date for this period (from now)
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .last180Days:
            return calendar.date(byAdding: .day, value: -180, to: now) ?? now
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }

    /// Number of days in this period (for rate calculations)
    var days: Int {
        switch self {
        case .today: return 1
        case .last7Days: return 7
        case .last30Days: return 30
        case .last90Days: return 90
        case .last180Days: return 180
        case .lastYear: return 365
        }
    }
}

/// Aggregated token usage with cost calculation
struct TokenUsageSummary: Sendable {
    let tokens: TokenCount
    let costUSD: Double
    let period: UsagePeriod

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

/// Errors related to token usage data loading
enum TokenUsageError: LocalizedError {
    case noLogsDirectory
    case noLogFiles
    case fileReadError(Error)
    case parseError(Error)
    case swiftDataError(Error)
    case repositoryUnavailable

    var errorDescription: String? {
        switch self {
        case .noLogsDirectory:
            return "Claude logs directory not found. Use Claude CLI to generate logs."
        case .noLogFiles:
            return "No log files found. Token usage will appear after using Claude CLI."
        case .fileReadError(let error):
            return "Failed to read log files: \(error.localizedDescription)"
        case .parseError(let error):
            return "Failed to parse log data: \(error.localizedDescription)"
        case .swiftDataError(let error):
            return "Database error: \(error.localizedDescription)"
        case .repositoryUnavailable:
            return "Token usage storage is not available."
        }
    }

    var shortDescription: String {
        switch self {
        case .noLogsDirectory, .noLogFiles: return "No token data"
        case .fileReadError: return "File read error"
        case .parseError: return "Parse error"
        case .swiftDataError: return "Database error"
        case .repositoryUnavailable: return "Storage unavailable"
        }
    }
}
