//
//  UsageLogSource.swift
//  ClaudeMeter
//
//  Provider-agnostic token/cost log source abstraction.
//

import Foundation
import ClaudeMeterKit

/// A single usage record from a provider's local logs, normalized for aggregation.
struct ProviderUsageEntry: Sendable {
    let provider: Provider
    /// Model identifier as reported by the provider (used for pricing + by-model breakdown).
    let model: String
    /// Pricing-table key for `ModelPricing` (e.g. "anthropic", "openai").
    let pricingProviderKey: String
    let tokens: TokenCount
    let timestamp: Date
    /// Provider-scoped unique key for deduplication.
    let dedupKey: String
    /// Cost already computed by the provider, if trustworthy; nil → compute via `ModelPricing`.
    let precomputedCostUSD: Double?

    init(
        provider: Provider,
        model: String,
        pricingProviderKey: String? = nil,
        tokens: TokenCount,
        timestamp: Date,
        dedupKey: String,
        precomputedCostUSD: Double? = nil
    ) {
        self.provider = provider
        self.model = model
        self.pricingProviderKey = pricingProviderKey ?? provider.pricingProviderKey
        self.tokens = tokens
        self.timestamp = timestamp
        self.dedupKey = dedupKey
        self.precomputedCostUSD = precomputedCostUSD
    }
}

/// A source of token/cost usage data for a single provider, read from local logs.
protocol UsageLogSource: Actor {
    nonisolated var provider: Provider { get }

    /// Fetch usage entries with a timestamp at or after `since`.
    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry]
}
