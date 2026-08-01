//
//  UsageLogSource.swift
//  AgentUsage
//
//  Provider-agnostic token/cost log source abstraction.
//

import Foundation
import AgentUsageKit

/// A single usage record from a provider's local logs, normalized for aggregation.
nonisolated struct ProviderUsageEntry: Sendable {
    let provider: Provider
    /// Model identifier as reported by the provider (used for pricing + by-model breakdown).
    let model: String
    /// Pricing-table key for `ModelPricing` (e.g. "anthropic", "openai").
    let pricingProviderKey: String
    let tokens: TokenCount
    let timestamp: Date
    /// Provider-scoped unique key for deduplication.
    let dedupKey: String
    /// Provider session identifier used for session-level usage aggregation.
    let sessionID: String
    /// Configured reasoning effort recorded by the provider, when available.
    let effortLevel: EffortLevel?
    /// True when this record belongs to a provider-spawned subagent session.
    let isSubagentSession: Bool
    /// Cost already computed by the provider, if trustworthy; nil → compute via `ModelPricing`.
    let precomputedCostUSD: Double?
    /// True when served in fast mode (Claude only); premium pricing applies. Non-Claude sources pass false.
    let fastMode: Bool

    init(
        provider: Provider,
        model: String,
        pricingProviderKey: String? = nil,
        tokens: TokenCount,
        timestamp: Date,
        dedupKey: String,
        sessionID: String? = nil,
        effortLevel: EffortLevel? = nil,
        isSubagentSession: Bool = false,
        precomputedCostUSD: Double? = nil,
        fastMode: Bool = false
    ) {
        self.provider = provider
        self.model = model
        self.pricingProviderKey = pricingProviderKey ?? provider.pricingProviderKey
        self.tokens = tokens
        self.timestamp = timestamp
        self.dedupKey = dedupKey
        self.sessionID = sessionID ?? dedupKey
        self.effortLevel = effortLevel
        self.isSubagentSession = isSubagentSession
        self.precomputedCostUSD = precomputedCostUSD
        self.fastMode = fastMode
    }
}

/// A source of token/cost usage data for a single provider, read from local logs.
protocol UsageLogSource: Actor {
    nonisolated var provider: Provider { get }

    /// Fetch usage entries with a timestamp at or after `since`.
    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry]
}
