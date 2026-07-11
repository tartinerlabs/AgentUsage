//
//  TokenUsage.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit

/// Pricing per million tokens (MTok) for Claude models
enum ModelPricing: Sendable {
    struct Rates: Sendable {
        let inputPerMTok: Double
        let outputPerMTok: Double
        /// 5-minute ephemeral cache write rate (1.25× base input per Anthropic).
        let cacheWritePerMTok: Double
        let cacheReadPerMTok: Double
        /// 1-hour ephemeral cache write rate (2× base input per Anthropic). Defaults to 2× input.
        let cacheWrite1hPerMTok: Double

        init(
            inputPerMTok: Double,
            outputPerMTok: Double,
            cacheWritePerMTok: Double,
            cacheReadPerMTok: Double,
            cacheWrite1hPerMTok: Double? = nil
        ) {
            self.inputPerMTok = inputPerMTok
            self.outputPerMTok = outputPerMTok
            self.cacheWritePerMTok = cacheWritePerMTok
            self.cacheReadPerMTok = cacheReadPerMTok
            self.cacheWrite1hPerMTok = cacheWrite1hPerMTok ?? (inputPerMTok * 2)
        }
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

    nonisolated static let sonnet5 = Rates(
        inputPerMTok: 3.0,
        outputPerMTok: 15.0,
        cacheWritePerMTok: 3.75,
        cacheReadPerMTok: 0.30
    )

    nonisolated static let fable5 = Rates(
        inputPerMTok: 10.0,
        outputPerMTok: 50.0,
        cacheWritePerMTok: 12.50,
        cacheReadPerMTok: 1.00
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

    nonisolated static let gpt55 = Rates(
        inputPerMTok: 5.0,
        outputPerMTok: 30.0,
        cacheWritePerMTok: 0,
        cacheReadPerMTok: 0.50
    )

    nonisolated static let gpt55Priority = Rates(
        inputPerMTok: 12.50,
        outputPerMTok: 75.0,
        cacheWritePerMTok: 0,
        cacheReadPerMTok: 1.25
    )

    nonisolated static let gpt54 = Rates(
        inputPerMTok: 2.50,
        outputPerMTok: 15.0,
        cacheWritePerMTok: 0,
        cacheReadPerMTok: 0.25
    )

    nonisolated static let gpt54Mini = Rates(
        inputPerMTok: 0.75,
        outputPerMTok: 4.50,
        cacheWritePerMTok: 0,
        cacheReadPerMTok: 0.075
    )

    nonisolated static let gpt53Codex = Rates(
        inputPerMTok: 1.75,
        outputPerMTok: 14.0,
        cacheWritePerMTok: 0,
        cacheReadPerMTok: 0.175
    )

    /// Get pricing rates for a model name
    nonisolated static func rates(for model: String) -> Rates? {
        if let rates = LiteLLMPricingCache.shared.rates(forProvider: "anthropic", model: model) {
            return rates
        }

        return fallbackRates(for: model)
    }

    /// Static fallback used only when LiteLLM pricing has not been cached yet.
    nonisolated static func fallbackRates(for model: String) -> Rates? {
        let lowercased = model.lowercased()

        if lowercased.contains("fable-5") || lowercased.contains("fable.5") {
            return fable5
        } else if lowercased.contains("opus-4-8") || lowercased.contains("opus-4.8") {
            return opus45
        } else if lowercased.contains("opus-4-7") || lowercased.contains("opus-4.7") {
            return opus45
        } else if lowercased.contains("opus-4-6") || lowercased.contains("opus-4.6") {
            return opus45
        } else if lowercased.contains("opus-4-5") || lowercased.contains("opus-4.5") {
            return opus45
        } else if lowercased.contains("sonnet-5") || lowercased.contains("sonnet.5") {
            return sonnet5
        } else if lowercased.contains("sonnet-4-6") || lowercased.contains("sonnet-4.6") {
            return sonnet45
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

    nonisolated static func rates(forProvider provider: String, model: String) -> Rates? {
        if let rates = LiteLLMPricingCache.shared.rates(forProvider: provider, model: model) {
            return rates
        }

        return fallbackRates(forProvider: provider, model: model)
    }

    /// Static fallback used only when LiteLLM pricing has not been cached yet.
    nonisolated static func fallbackRates(forProvider provider: String, model: String) -> Rates? {
        let lowercasedProvider = provider.lowercased()
        let lowercasedModel = model.lowercased()

        if lowercasedProvider == "anthropic" {
            return rates(for: model)
        }

        if lowercasedProvider == "openai" {
            if lowercasedModel == "codex-auto-review" || lowercasedModel.contains("gpt-5.3-codex") {
                return gpt53Codex
            } else if lowercasedModel.contains("gpt-5.5-fast") {
                return gpt55Priority
            } else if lowercasedModel.contains("gpt-5.5") {
                return gpt55
            } else if lowercasedModel.contains("gpt-5.4-mini") {
                return gpt54Mini
            } else if lowercasedModel.contains("gpt-5.4") {
                return gpt54
            }
        }

        return nil
    }

    nonisolated static func costUSD(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        reasoningTokens: Int,
        cacheWrite1hTokens: Int = 0,
        fastMode: Bool = false
    ) -> Double? {
        guard let rates = rates(forProvider: provider, model: model) else { return nil }
        let billsReasoningAsOutput = provider.lowercased() == "openai"
        let billableOutputTokens = outputTokens + (billsReasoningAsOutput ? reasoningTokens : 0)
        // `cacheWrite1hTokens` is a subset of `cacheWriteTokens`; the remainder is 5-minute cache.
        let cacheWrite5mTokens = max(0, cacheWriteTokens - cacheWrite1hTokens)

        var cost = (
            Double(inputTokens) * rates.inputPerMTok
            + Double(billableOutputTokens) * rates.outputPerMTok
            + Double(cacheWrite5mTokens) * rates.cacheWritePerMTok
            + Double(cacheWrite1hTokens) * rates.cacheWrite1hPerMTok
            + Double(cacheReadTokens) * rates.cacheReadPerMTok
        ) / 1_000_000

        // Fast mode scales input, output, and (stacked) cache rates by the same per-model factor,
        // so multiplying the whole standard-computed cost is exact. Verified vs platform.claude.com.
        if fastMode {
            cost *= fastMultiplier(provider: provider, model: model)
        }
        return cost
    }

    /// Fast-mode premium multiplier (research preview, Opus-only) applied when `usage.speed == "fast"`.
    /// Opus 4.8 = 2×, Opus 4.7/4.6 = 6×; all other models 1×. Verified against official pricing.
    nonisolated static func fastMultiplier(provider: String, model: String) -> Double {
        guard provider.lowercased() == "anthropic" else { return 1.0 }
        let m = model.lowercased()
        if m.contains("opus-4-8") || m.contains("opus-4.8") { return 2.0 }
        if m.contains("opus-4-7") || m.contains("opus-4.7") { return 6.0 }
        if m.contains("opus-4-6") || m.contains("opus-4.6") { return 6.0 }
        return 1.0
    }
}

/// LiteLLM-backed pricing cache.
///
/// LiteLLM is the source of truth for model prices. This cache refreshes from a
/// configured LiteLLM proxy (`LITELLM_PROXY_URL`) when available, otherwise from
/// LiteLLM's hosted model cost map. The legacy hardcoded table remains only as
/// an offline fallback before the first successful refresh.
final class LiteLLMPricingCache: @unchecked Sendable {
    static let shared = LiteLLMPricingCache()

    private static let defaultCostMapURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let cacheDataKey = "LiteLLMPricingCache.data"
    private static let cacheUpdatedAtKey = "LiteLLMPricingCache.updatedAt"
    private static let cacheSourceKey = "LiteLLMPricingCache.source"

    private struct ModelInfo: Codable, Sendable {
        let aliases: [String]?
        let inputCostPerToken: Double?
        let outputCostPerToken: Double?
        let cacheCreationInputTokenCost: Double?
        let cacheReadInputTokenCost: Double?
        let outputCostPerReasoningToken: Double?

        enum CodingKeys: String, CodingKey {
            case aliases
            case inputCostPerToken = "input_cost_per_token"
            case outputCostPerToken = "output_cost_per_token"
            case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
            case cacheReadInputTokenCost = "cache_read_input_token_cost"
            case outputCostPerReasoningToken = "output_cost_per_reasoning_token"
        }

        var rates: ModelPricing.Rates? {
            guard let inputCostPerToken, let outputCostPerToken else { return nil }
            return ModelPricing.Rates(
                inputPerMTok: inputCostPerToken * 1_000_000,
                outputPerMTok: outputCostPerToken * 1_000_000,
                cacheWritePerMTok: (cacheCreationInputTokenCost ?? inputCostPerToken) * 1_000_000,
                cacheReadPerMTok: (cacheReadInputTokenCost ?? inputCostPerToken) * 1_000_000
            )
        }
    }

    private struct ProxyModelInfo: Decodable, Sendable {
        let modelName: String?
        let modelInfo: ModelInfo?
        let directModelInfo: ModelInfo?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case modelInfo = "model_info"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
            modelInfo = try container.decodeIfPresent(ModelInfo.self, forKey: .modelInfo)
            directModelInfo = try? ModelInfo(from: decoder)
        }
    }

    private struct ProxyModelInfoResponse: Decodable, Sendable {
        let data: [ProxyModelInfo]
    }

    private let lock = NSLock()
    private var map: [String: ModelInfo]?
    private var lastRefreshTask: Task<Void, Never>?

    private init() {}

    var sourceDescription: String? {
        UserDefaults.standard.string(forKey: Self.cacheSourceKey)
    }

    func refreshIfNeeded(
        ttl: TimeInterval = 24 * 60 * 60,
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        let lastUpdated = UserDefaults.standard.double(forKey: Self.cacheUpdatedAtKey)
        if lastUpdated > 0, Date().timeIntervalSince1970 - lastUpdated < ttl, ratesMap() != nil {
            return
        }

        lock.lock()
        if let lastRefreshTask {
            lock.unlock()
            await lastRefreshTask.value
            return
        }
        let task = Task<Void, Never> {
            await self.refresh(session: session, environment: environment)
        }
        lastRefreshTask = task
        lock.unlock()

        await task.value

        lock.lock()
        lastRefreshTask = nil
        lock.unlock()
    }

    func refresh(
        session: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        if let proxyURL = Self.proxyModelInfoURL(environment: environment),
           let data = try? await Self.fetch(url: proxyURL, session: session, bearerToken: Self.proxyToken(environment: environment)),
           let map = Self.decodeProxyModelInfo(data) {
            store(map: map, source: "LiteLLM Proxy")
            return
        }

        let costMapURL = Self.costMapURL(environment: environment)
        if let data = try? await Self.fetch(url: costMapURL, session: session, bearerToken: nil),
           let map = Self.decodeCostMap(data) {
            store(map: map, source: "LiteLLM Hosted Map")
        }
    }

    func rates(forProvider provider: String, model: String) -> ModelPricing.Rates? {
        guard let map = ratesMap() else { return nil }
        for key in lookupKeys(provider: provider, model: model) {
            if let rates = map[key]?.rates {
                return rates
            }
        }
        return nil
    }

    #if DEBUG
    func clearForTesting() {
        UserDefaults.standard.removeObject(forKey: Self.cacheDataKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheUpdatedAtKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheSourceKey)
        lock.lock()
        map = nil
        lock.unlock()
    }
    #endif

    private func ratesMap() -> [String: ModelInfo]? {
        lock.lock()
        if let map {
            lock.unlock()
            return map
        }
        lock.unlock()

        guard let data = UserDefaults.standard.data(forKey: Self.cacheDataKey),
              let decoded = try? JSONDecoder().decode([String: ModelInfo].self, from: data) else {
            return nil
        }

        lock.lock()
        map = decoded
        lock.unlock()
        return decoded
    }

    private func store(map: [String: ModelInfo], source: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheDataKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheUpdatedAtKey)
        UserDefaults.standard.set(source, forKey: Self.cacheSourceKey)

        lock.lock()
        self.map = map
        lock.unlock()
    }

    private func lookupKeys(provider: String, model: String) -> [String] {
        let normalizedProvider = normalize(provider)
        let normalizedModel = normalize(model)
        let modelWithoutLiteLLMPrefix = normalizedModel.removingPrefix("litellm/")

        var keys = [
            normalizedModel,
            modelWithoutLiteLLMPrefix,
            "\(normalizedProvider)/\(modelWithoutLiteLLMPrefix)",
            "\(normalizedProvider).\(modelWithoutLiteLLMPrefix)"
        ]

        if normalizedProvider == "litellm" {
            keys.append(contentsOf: [
                "anthropic/\(modelWithoutLiteLLMPrefix)",
                "anthropic.\(modelWithoutLiteLLMPrefix)",
                "openai/\(modelWithoutLiteLLMPrefix)",
                "openai.\(modelWithoutLiteLLMPrefix)"
            ])
        }

        return Array(Set(keys))
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func proxyModelInfoURL(environment: [String: String]) -> URL? {
        guard let raw = environment["LITELLM_PROXY_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let base = URL(string: raw) else { return nil }
        return base.appendingPathComponent("model/info")
    }

    private static func proxyToken(environment: [String: String]) -> String? {
        let token = environment["LITELLM_API_KEY"] ?? environment["LITELLM_MASTER_KEY"]
        return token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func costMapURL(environment: [String: String]) -> URL {
        guard let raw = environment["LITELLM_MODEL_COST_MAP_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return defaultCostMapURL
        }
        return url
    }

    private static func fetch(url: URL, session: URLSession, bearerToken: String?) async throws -> Data {
        var request = URLRequest(url: url)
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func decodeCostMap(_ data: Data) -> [String: ModelInfo]? {
        guard let decoded = try? JSONDecoder().decode([String: ModelInfo].self, from: data) else { return nil }
        return expandAliases(decoded)
    }

    private static func decodeProxyModelInfo(_ data: Data) -> [String: ModelInfo]? {
        if let response = try? JSONDecoder().decode(ProxyModelInfoResponse.self, from: data) {
            var result: [String: ModelInfo] = [:]
            for item in response.data {
                guard let modelName = item.modelName?.nilIfEmpty,
                      let modelInfo = item.modelInfo ?? item.directModelInfo else { continue }
                result[modelName.lowercased()] = modelInfo
            }
            return result.isEmpty ? nil : expandAliases(result)
        }

        return decodeCostMap(data)
    }

    private static func expandAliases(_ map: [String: ModelInfo]) -> [String: ModelInfo] {
        var expanded: [String: ModelInfo] = [:]
        for (key, info) in map {
            expanded[key.lowercased()] = info
            for alias in info.aliases ?? [] {
                expanded[alias.lowercased()] = info
            }
        }
        return expanded
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

/// Token counts from a single API request
struct TokenCount: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// Reasoning tokens (Codex/OpenCode report these; Claude leaves it 0).
    let reasoningTokens: Int
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL (billed at 2× input). 0 when unknown.
    let cacheCreation1hTokens: Int

    init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        reasoningTokens: Int = 0,
        cacheCreation1hTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningTokens = reasoningTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
    }

    var totalTokens: Int {
        // `cacheCreation1hTokens` is a subset of `cacheCreationTokens`, so it is not added here.
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens + reasoningTokens
    }

    nonisolated static let zero = TokenCount(inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0)
}

nonisolated func + (lhs: TokenCount, rhs: TokenCount) -> TokenCount {
    TokenCount(
        inputTokens: lhs.inputTokens + rhs.inputTokens,
        outputTokens: lhs.outputTokens + rhs.outputTokens,
        cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
        cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
        reasoningTokens: lhs.reasoningTokens + rhs.reasoningTokens,
        cacheCreation1hTokens: lhs.cacheCreation1hTokens + rhs.cacheCreation1hTokens
    )
}

/// Usage entry parsed from JSONL log
struct UsageEntry: Sendable {
    let model: String
    let tokens: TokenCount
    let timestamp: Date
    /// True when the request was served in fast mode (`usage.speed == "fast"`); premium pricing applies.
    let fastMode: Bool

    init(model: String, tokens: TokenCount, timestamp: Date, fastMode: Bool = false) {
        self.model = model
        self.tokens = tokens
        self.timestamp = timestamp
        self.fastMode = fastMode
    }
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

/// A single day's token/cost aggregate (for daily trend sparklines).
struct DailyTokenPoint: Sendable {
    let date: Date
    let costUSD: Double
    let tokens: Int
}

/// Full per-provider detail for the detail page.
struct ProviderDetail: Sendable {
    let today: TokenUsageSummary
    let yesterday: TokenUsageSummary
    let last30Days: TokenUsageSummary
    /// 30-day token totals per model.
    let byModel: [String: TokenCount]
    /// Daily cost for the last 30 days, oldest → newest (sparkline).
    let dailyCosts: [Double]

    /// Models sorted by total tokens, descending, with share of the 30-day total.
    var modelShares: [(model: String, tokens: Int, percent: Double)] {
        let totals = byModel.mapValues { $0.totalTokens }
        let grand = totals.values.reduce(0, +)
        guard grand > 0 else { return [] }
        return totals
            .map { (model: $0.key, tokens: $0.value, percent: Double($0.value) / Double(grand) * 100) }
            .sorted { $0.tokens > $1.tokens }
    }
}

/// Complete token usage snapshot
struct TokenUsageSnapshot: Sendable {
    let today: TokenUsageSummary
    let last30Days: TokenUsageSummary
    let byModel: [String: TokenCount]
    /// Per-provider 30-day breakdown (Claude / Codex / OpenCode).
    let byProvider: [Provider: TokenUsageSummary]
    let fetchedAt: Date

    init(
        today: TokenUsageSummary,
        last30Days: TokenUsageSummary,
        byModel: [String: TokenCount],
        byProvider: [Provider: TokenUsageSummary] = [:],
        fetchedAt: Date
    ) {
        self.today = today
        self.last30Days = last30Days
        self.byModel = byModel
        self.byProvider = byProvider
        self.fetchedAt = fetchedAt
    }
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
