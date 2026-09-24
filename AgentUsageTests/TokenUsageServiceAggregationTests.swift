//
//  TokenUsageServiceAggregationTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage
import AgentUsageKit

@Suite("TokenUsageService extra-provider aggregation", .serialized)
struct TokenUsageServiceAggregationTests {
    /// The same Codex session can reach the service twice, e.g. from `sessions` and
    /// `archived_sessions`, or from two sources. It must be counted once, and each
    /// provider's cost must come from its own fallback rates.
    @Test func dedupesAcrossSourcesAndPricesEachProviderWithFallbackRates() async throws {
        // Fallback pricing only: no LiteLLM map may be cached.
        LiteLLMPricingCache.shared.clearForTesting()
        defer { LiteLLMPricingCache.shared.clearForTesting() }

        let now = Date()
        let codexTokens = TokenCount(
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cacheCreationTokens: 0,
            cacheReadTokens: 200_000
        )
        let codexEntry = ProviderUsageEntry(
            provider: .codex,
            model: "gpt-5.5",
            pricingProviderKey: "openai",
            tokens: codexTokens,
            timestamp: now,
            dedupKey: "codex:session-1"
        )
        let grokEntry = ProviderUsageEntry(
            provider: .grok,
            model: "grok-4.6",
            pricingProviderKey: "xai",
            tokens: TokenCount(
                inputTokens: 500_000,
                outputTokens: 50_000,
                cacheCreationTokens: 100_000,
                cacheReadTokens: 1_000_000
            ),
            timestamp: now,
            dedupKey: "grok:session-1"
        )
        let service = TokenUsageService(extraSources: [
            StaticUsageLogSource(provider: .codex, entries: [codexEntry]),
            // A second source replays the same Codex session under the same key.
            StaticUsageLogSource(provider: .codex, entries: [codexEntry]),
            StaticUsageLogSource(provider: .grok, entries: [grokEntry]),
        ])

        let details = await service.fetchExtraProviderDetails(since: .distantPast)

        let codex = try #require(details[.codex])
        let grok = try #require(details[.grok])

        // gpt-5.5 fallback: $5 input, $30 output, $0.50 cache read per MTok.
        let gpt55 = ModelPricing.gpt55
        let expectedCodexCost = (1_000_000 * gpt55.inputPerMTok
            + 100_000 * gpt55.outputPerMTok
            + 200_000 * gpt55.cacheReadPerMTok) / 1_000_000
        #expect(abs(expectedCodexCost - 8.10) < 1e-9)
        #expect(codex.last30Days.tokens.totalTokens == 1_300_000)
        #expect(codex.last30Days.tokens.inputTokens == 1_000_000)
        #expect(abs(codex.last30Days.costUSD - expectedCodexCost) < 1e-9)
        #expect(abs(codex.today.costUSD - expectedCodexCost) < 1e-9)
        #expect(codex.byModel["gpt-5.5"]?.totalTokens == 1_300_000)

        // grok-4.6 fallback: $2 input, $6 output, $2 cache write, $0.50 cache read per MTok.
        let grok46 = ModelPricing.grok46
        let expectedGrokCost = (500_000 * grok46.inputPerMTok
            + 50_000 * grok46.outputPerMTok
            + 100_000 * grok46.cacheWritePerMTok
            + 1_000_000 * grok46.cacheReadPerMTok) / 1_000_000
        #expect(abs(expectedGrokCost - 2.00) < 1e-9)
        #expect(grok.last30Days.tokens.totalTokens == 1_650_000)
        #expect(abs(grok.last30Days.costUSD - expectedGrokCost) < 1e-9)

        let samples = await service.fetchExtraProviderEffortSamples(since: .distantPast)
        #expect(samples.filter { $0.provider == .codex }.count == 1)
        #expect(samples.filter { $0.provider == .grok }.count == 1)
    }
}
#endif
