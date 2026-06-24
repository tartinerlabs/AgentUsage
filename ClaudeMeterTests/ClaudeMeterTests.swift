//
//  ClaudeMeterTests.swift
//  ClaudeMeterTests
//
//  Created by Ru Chern Chong on 31/12/25.
//

import Testing
import Foundation
@testable import ClaudeMeter

// MARK: - ModelPricing Tests

@Suite("ModelPricing", .serialized)
struct ModelPricingTests {

    // MARK: - Rate Values

    @Test func opus45RatesAreCorrect() {
        let rates = ModelPricing.opus45
        #expect(rates.inputPerMTok == 5.0)
        #expect(rates.outputPerMTok == 25.0)
        #expect(rates.cacheWritePerMTok == 6.25)
        #expect(rates.cacheReadPerMTok == 0.50)
    }

    @Test func sonnet45RatesAreCorrect() {
        let rates = ModelPricing.sonnet45
        #expect(rates.inputPerMTok == 3.0)
        #expect(rates.outputPerMTok == 15.0)
        #expect(rates.cacheWritePerMTok == 3.75)
        #expect(rates.cacheReadPerMTok == 0.30)
    }

    @Test func sonnet4RatesAreCorrect() {
        let rates = ModelPricing.sonnet4
        #expect(rates.inputPerMTok == 3.0)
        #expect(rates.outputPerMTok == 15.0)
        #expect(rates.cacheWritePerMTok == 3.75)
        #expect(rates.cacheReadPerMTok == 0.30)
    }

    @Test func haiku45RatesAreCorrect() {
        let rates = ModelPricing.haiku45
        #expect(rates.inputPerMTok == 1.0)
        #expect(rates.outputPerMTok == 5.0)
        #expect(rates.cacheWritePerMTok == 1.25)
        #expect(rates.cacheReadPerMTok == 0.10)
    }

    @Test func haiku35RatesAreCorrect() {
        let rates = ModelPricing.haiku35
        #expect(rates.inputPerMTok == 0.80)
        #expect(rates.outputPerMTok == 4.0)
        #expect(rates.cacheWritePerMTok == 1.0)
        #expect(rates.cacheReadPerMTok == 0.08)
    }

    // MARK: - Model Name Matching

    @Test func matchesOpus45Variants() {
        #expect(ModelPricing.rates(for: "claude-opus-4-8") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4-7") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4-6") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4-5") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4.5") != nil)
        #expect(ModelPricing.rates(for: "CLAUDE-OPUS-4-5") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4-5-20250101") != nil)

        let rates = ModelPricing.rates(for: "claude-opus-4-5")!
        #expect(rates.inputPerMTok == 5.0)
    }

    @Test func matchesSonnet45Variants() {
        #expect(ModelPricing.rates(for: "claude-sonnet-4-6") != nil)
        #expect(ModelPricing.rates(for: "claude-sonnet-4-5") != nil)
        #expect(ModelPricing.rates(for: "claude-sonnet-4.5") != nil)
        #expect(ModelPricing.rates(for: "claude-3-5-sonnet-4-5") != nil)

        let rates = ModelPricing.rates(for: "claude-sonnet-4-5")!
        #expect(rates.inputPerMTok == 3.0)
    }

    @Test func matchesSonnet4Variants() {
        #expect(ModelPricing.rates(for: "claude-sonnet-4") != nil)
        #expect(ModelPricing.rates(for: "claude-sonnet-4-20250101") != nil)

        let rates = ModelPricing.rates(for: "claude-sonnet-4")!
        #expect(rates.inputPerMTok == 3.0)
    }

    @Test func sonnet45TakesPriorityOverSonnet4() {
        // sonnet-4-5 should match sonnet45, not sonnet4
        let rates = ModelPricing.rates(for: "claude-sonnet-4-5")!
        #expect(rates.inputPerMTok == 3.0) // Both are same price, but ensure it matches
    }

    @Test func matchesHaiku45Variants() {
        #expect(ModelPricing.rates(for: "claude-haiku-4-5") != nil)
        #expect(ModelPricing.rates(for: "claude-haiku-4.5") != nil)

        let rates = ModelPricing.rates(for: "claude-haiku-4-5")!
        #expect(rates.inputPerMTok == 1.0)
    }

    @Test func matchesHaiku35Variants() {
        #expect(ModelPricing.rates(for: "claude-haiku-3-5") != nil)
        #expect(ModelPricing.rates(for: "claude-haiku-3.5") != nil)
        #expect(ModelPricing.rates(for: "claude-3-haiku") != nil) // Just contains "haiku"

        let rates = ModelPricing.rates(for: "claude-haiku-3-5")!
        #expect(rates.inputPerMTok == 0.80)
    }

    @Test func returnsNilForUnknownModel() {
        // gpt-4 is priced by the live LiteLLM cost map, so only the static
        // fallback is expected to reject it.
        #expect(ModelPricing.fallbackRates(for: "gpt-4") == nil)
        #expect(ModelPricing.rates(for: "unknown-model") == nil)
        #expect(ModelPricing.rates(for: "") == nil)
    }

    @Test func caseInsensitiveMatching() {
        #expect(ModelPricing.rates(for: "CLAUDE-OPUS-4-5") != nil)
        #expect(ModelPricing.rates(for: "Claude-Opus-4-5") != nil)
        #expect(ModelPricing.rates(for: "claude-opus-4-5") != nil)
    }

    @Test func matchesOpenAIProviderModels() {
        #expect(ModelPricing.rates(forProvider: "openai", model: "gpt-5.5")?.inputPerMTok == 5.0)
        #expect(ModelPricing.rates(forProvider: "openai", model: "gpt-5.5-fast")?.inputPerMTok == 12.50)
        #expect(ModelPricing.rates(forProvider: "openai", model: "gpt-5.4")?.inputPerMTok == 2.50)
        #expect(ModelPricing.rates(forProvider: "openai", model: "gpt-5.4-mini")?.inputPerMTok == 0.75)
        #expect(ModelPricing.rates(forProvider: "openai", model: "codex-auto-review")?.inputPerMTok == 1.75)
        #expect(ModelPricing.rates(forProvider: "openai", model: "gpt-5.3-codex")?.inputPerMTok == 1.75)
    }

    @Test func liteLLMHostedCostMapPricesModels() async throws {
        LiteLLMPricingCache.shared.clearForTesting()
        defer { LiteLLMPricingCache.shared.clearForTesting() }

        let session = Self.urlSessionReturning("""
        {
          "claude-fable-5": {
            "input_cost_per_token": 0.000010,
            "output_cost_per_token": 0.000050,
            "cache_creation_input_token_cost": 0.0000125,
            "cache_read_input_token_cost": 0.000001,
            "litellm_provider": "anthropic"
          }
        }
        """)

        await LiteLLMPricingCache.shared.refresh(
            session: session,
            environment: ["LITELLM_MODEL_COST_MAP_URL": "https://pricing.test/map.json"]
        )

        let rates = try #require(ModelPricing.rates(forProvider: "litellm", model: "claude-fable-5"))
        #expect(rates.inputPerMTok == 10.0)
        #expect(rates.outputPerMTok == 50.0)
        #expect(rates.cacheWritePerMTok == 12.5)
        #expect(rates.cacheReadPerMTok == 1.0)
    }

    @Test func liteLLMProxyModelInfoOverridesHostedCostMap() async throws {
        LiteLLMPricingCache.shared.clearForTesting()
        defer { LiteLLMPricingCache.shared.clearForTesting() }

        let session = Self.urlSessionReturning("""
        {
          "data": [
            {
              "model_name": "claude-mythos-5",
              "model_info": {
                "input_cost_per_token": 0.000010,
                "output_cost_per_token": 0.000050,
                "cache_creation_input_token_cost": 0.0000125,
                "cache_read_input_token_cost": 0.000001
              }
            }
          ]
        }
        """)

        await LiteLLMPricingCache.shared.refresh(
            session: session,
            environment: ["LITELLM_PROXY_URL": "https://litellm.test"]
        )

        let rates = try #require(ModelPricing.rates(forProvider: "litellm", model: "claude-mythos-5"))
        #expect(rates.inputPerMTok == 10.0)
        #expect(rates.outputPerMTok == 50.0)
    }

    @Test func openAIReasoningTokensAreBilledAsOutput() {
        let cost = ModelPricing.costUSD(
            provider: "openai",
            model: "codex-auto-review",
            inputTokens: 0,
            outputTokens: 1_000_000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            reasoningTokens: 1_000_000
        )

        #expect(cost == 28.0)
    }

    private static func urlSessionReturning(_ body: String) -> URLSession {
        LiteLLMPricingURLProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiteLLMPricingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class LiteLLMPricingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - TokenCount Tests

@Suite("TokenCount")
struct TokenCountTests {

    @Test func totalTokensCalculation() {
        let tokens = TokenCount(
            inputTokens: 1000,
            outputTokens: 500,
            cacheCreationTokens: 200,
            cacheReadTokens: 100
        )
        #expect(tokens.totalTokens == 1800)
    }

    @Test func zeroTokenCount() {
        #expect(TokenCount.zero.inputTokens == 0)
        #expect(TokenCount.zero.outputTokens == 0)
        #expect(TokenCount.zero.cacheCreationTokens == 0)
        #expect(TokenCount.zero.cacheReadTokens == 0)
        #expect(TokenCount.zero.totalTokens == 0)
    }

    @Test func addition() {
        let a = TokenCount(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 20, cacheReadTokens: 10)
        let b = TokenCount(inputTokens: 200, outputTokens: 100, cacheCreationTokens: 40, cacheReadTokens: 20)
        let sum = a + b

        #expect(sum.inputTokens == 300)
        #expect(sum.outputTokens == 150)
        #expect(sum.cacheCreationTokens == 60)
        #expect(sum.cacheReadTokens == 30)
        #expect(sum.totalTokens == 540)
    }

    @Test func additionWithZero() {
        let a = TokenCount(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 20, cacheReadTokens: 10)
        let sum = a + TokenCount.zero

        #expect(sum.inputTokens == 100)
        #expect(sum.outputTokens == 50)
        #expect(sum.cacheCreationTokens == 20)
        #expect(sum.cacheReadTokens == 10)
    }
}

// MARK: - UsagePeriod Tests

@Suite("UsagePeriod")
struct UsagePeriodTests {

    @Test func rawValues() {
        #expect(UsagePeriod.today.rawValue == "Today")
        #expect(UsagePeriod.last7Days.rawValue == "7 Days")
        #expect(UsagePeriod.last30Days.rawValue == "30 Days")
        #expect(UsagePeriod.last90Days.rawValue == "90 Days")
        #expect(UsagePeriod.last180Days.rawValue == "180 Days")
        #expect(UsagePeriod.lastYear.rawValue == "Year")
    }

    @Test func days() {
        #expect(UsagePeriod.today.days == 1)
        #expect(UsagePeriod.last7Days.days == 7)
        #expect(UsagePeriod.last30Days.days == 30)
        #expect(UsagePeriod.last90Days.days == 90)
        #expect(UsagePeriod.last180Days.days == 180)
        #expect(UsagePeriod.lastYear.days == 365)
    }

    @Test func allCasesExist() {
        #expect(UsagePeriod.allCases.count == 6)
    }

    @Test func identifiable() {
        #expect(UsagePeriod.today.id == "Today")
        #expect(UsagePeriod.last30Days.id == "30 Days")
    }

    @Test func startDateForTodayIsStartOfDay() {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        #expect(UsagePeriod.today.startDate == startOfToday)
    }

    @Test func startDateFor7DaysIsInPast() {
        let now = Date()
        let startDate = UsagePeriod.last7Days.startDate

        // Should be approximately 7 days ago (allow for test execution time)
        let daysDifference = Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 0
        #expect(daysDifference >= 6 && daysDifference <= 7)
    }

    @Test func startDateFor30DaysIsInPast() {
        let now = Date()
        let startDate = UsagePeriod.last30Days.startDate

        let daysDifference = Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 0
        #expect(daysDifference >= 29 && daysDifference <= 30)
    }

    @Test func startDateForYearIsInPast() {
        let now = Date()
        let startDate = UsagePeriod.lastYear.startDate

        let daysDifference = Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 0
        #expect(daysDifference >= 364 && daysDifference <= 366)
    }
}

// MARK: - TokenUsageSummary Tests

@Suite("TokenUsageSummary")
struct TokenUsageSummaryTests {

    @Test func formattedCost() {
        let summary = TokenUsageSummary(
            tokens: TokenCount(inputTokens: 1000, outputTokens: 500, cacheCreationTokens: 0, cacheReadTokens: 0),
            costUSD: 12.345,
            period: .today
        )
        #expect(summary.formattedCost == "$12.35")
    }

    @Test func formattedCostZero() {
        let summary = TokenUsageSummary(
            tokens: TokenCount.zero,
            costUSD: 0,
            period: .today
        )
        #expect(summary.formattedCost == "$0.00")
    }

    @Test func formattedCostSmall() {
        let summary = TokenUsageSummary(
            tokens: TokenCount.zero,
            costUSD: 0.005,
            period: .today
        )
        #expect(summary.formattedCost == "$0.01")
    }

    @Test func formattedTokensSmall() {
        let summary = TokenUsageSummary(
            tokens: TokenCount(inputTokens: 500, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            costUSD: 0,
            period: .today
        )
        #expect(summary.formattedTokens == "500")
    }

    @Test func formattedTokensThousands() {
        let summary = TokenUsageSummary(
            tokens: TokenCount(inputTokens: 50000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            costUSD: 0,
            period: .today
        )
        #expect(summary.formattedTokens == "50.0K")
    }

    @Test func formattedTokensMillions() {
        let summary = TokenUsageSummary(
            tokens: TokenCount(inputTokens: 2500000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
            costUSD: 0,
            period: .today
        )
        #expect(summary.formattedTokens == "2.5M")
    }
}

// MARK: - TokenUsageError Tests

@Suite("TokenUsageError")
struct TokenUsageErrorTests {

    @Test func shortDescriptions() {
        #expect(TokenUsageError.noLogsDirectory.shortDescription == "No token data")
        #expect(TokenUsageError.noLogFiles.shortDescription == "No token data")
        #expect(TokenUsageError.fileReadError(NSError(domain: "", code: 0)).shortDescription == "File read error")
        #expect(TokenUsageError.parseError(NSError(domain: "", code: 0)).shortDescription == "Parse error")
        #expect(TokenUsageError.swiftDataError(NSError(domain: "", code: 0)).shortDescription == "Database error")
        #expect(TokenUsageError.repositoryUnavailable.shortDescription == "Storage unavailable")
    }

    @Test func errorDescriptions() {
        #expect(TokenUsageError.noLogsDirectory.errorDescription?.contains("logs directory not found") == true)
        #expect(TokenUsageError.noLogFiles.errorDescription?.contains("No log files") == true)
        #expect(TokenUsageError.repositoryUnavailable.errorDescription?.contains("not available") == true)
    }
}

// MARK: - ClaudeOAuthCredentials Tests

@Suite("ClaudeOAuthCredentials")
struct ClaudeOAuthCredentialsTests {

    // MARK: - Expiration

    @Test func isExpiredWhenPast() {
        let pastTime = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000 // 1 hour ago in ms
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: pastTime,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.isExpired == true)
    }

    @Test func isNotExpiredWhenFuture() {
        let futureTime = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000 // 1 hour from now in ms
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: futureTime,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.isExpired == false)
    }

    @Test func isNotExpiredWhenNoExpiresAt() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.isExpired == false)
    }

    @Test func expiresAtDateConversion() {
        let timestamp: Double = 1700000000000 // ms since epoch
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: timestamp,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.expiresAtDate == Date(timeIntervalSince1970: 1700000000))
    }

    @Test func expiresAtDateNilWhenNoExpiry() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.expiresAtDate == nil)
    }

    // MARK: - Scope Validation

    @Test func hasRequiredScopeWhenPresent() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: ["user:profile", "other:scope"],
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.hasRequiredScope == true)
    }

    @Test func hasRequiredScopeWhenMissing() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: ["other:scope"],
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.hasRequiredScope == false)
    }

    @Test func hasRequiredScopeWhenNoScopes() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        // When scopes is nil, assume required scope is present (backwards compatibility)
        #expect(credentials.hasRequiredScope == true)
    }

    // MARK: - Plan Display Names

    @Test func planDisplayNameMax() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "max",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Max")
    }

    @Test func planDisplayNameClaudeMax() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "claude_max",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Max")
    }

    @Test func planDisplayNamePro() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "pro",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Pro")
    }

    @Test func planDisplayNameClaudePro() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "claude_pro",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Pro")
    }

    @Test func planDisplayNameTeam() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "team",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Team")
    }

    @Test func planDisplayNameClaudeTeam() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "claude_team",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Team")
    }

    @Test func planDisplayNameEnterprise() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "enterprise",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Enterprise")
    }

    @Test func planDisplayNameFree() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "free",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Free")
    }

    @Test func planDisplayNameUnknownCapitalized() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "custom_plan",
            rateLimitTier: nil
        )
        // Foundation's capitalized capitalizes each word
        #expect(credentials.planDisplayName == "Custom_Plan")
    }

    @Test func planDisplayNameDefaultsToFree() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Free")
    }

    @Test func planDisplayNameCaseInsensitive() {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            scopes: nil,
            subscriptionType: "MAX",
            rateLimitTier: nil
        )
        #expect(credentials.planDisplayName == "Max")
    }
}

// MARK: - CredentialsFile Tests

@Suite("CredentialsFile")
struct CredentialsFileTests {

    @Test func decodesFromJSON() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "test-token",
                "refreshToken": "refresh-token",
                "expiresAt": 1700000000000,
                "scopes": ["user:profile"],
                "subscriptionType": "pro",
                "rateLimitTier": "tier1"
            }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(CredentialsFile.self, from: json)

        #expect(file.claudeAiOauth?.accessToken == "test-token")
        #expect(file.claudeAiOauth?.refreshToken == "refresh-token")
        #expect(file.claudeAiOauth?.subscriptionType == "pro")
    }

    @Test func decodesWithNilOauth() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(CredentialsFile.self, from: json)

        #expect(file.claudeAiOauth == nil)
    }
}

// MARK: - Cost Model Accuracy (ccusage-derived)

@Suite("CostModelAccuracy", .serialized)
struct CostModelAccuracyTests {

    /// 1-hour ephemeral cache writes bill at 2× base input; 5-minute at 1.25×. (Verified vs official pricing.)
    @Test func oneHourCacheRateIsDoubleInput() {
        #expect(ModelPricing.opus45.cacheWrite1hPerMTok == 10.0)   // 2 × $5 input
        #expect(ModelPricing.opus45.cacheWritePerMTok == 6.25)     // 1.25 × $5 input (5-minute)
        #expect(ModelPricing.sonnet45.cacheWrite1hPerMTok == 6.0)  // 2 × $3 input
        #expect(ModelPricing.haiku45.cacheWrite1hPerMTok == 2.0)   // 2 × $1 input
    }

    /// Splitting a cache-creation bucket into a 1h subset raises cost by (1h − 5m) per token.
    @Test func oneHourCacheCostsMoreThanFiveMinute() {
        LiteLLMPricingCache.shared.clearForTesting()
        let model = "claude-opus-4-8-20260101"

        let all5m = ModelPricing.costUSD(
            provider: "anthropic", model: model,
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0,
            cacheWriteTokens: 1_000_000, reasoningTokens: 0,
            cacheWrite1hTokens: 0
        )
        let all1h = ModelPricing.costUSD(
            provider: "anthropic", model: model,
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0,
            cacheWriteTokens: 1_000_000, reasoningTokens: 0,
            cacheWrite1hTokens: 1_000_000
        )

        #expect(all5m == 6.25)  // 1M × $6.25 (5m)
        #expect(all1h == 10.0)  // 1M × $10.00 (1h)
    }

    @Test func fastMultiplierMatchesOfficialPricing() {
        #expect(ModelPricing.fastMultiplier(provider: "anthropic", model: "claude-opus-4-8-20260101") == 2.0)
        #expect(ModelPricing.fastMultiplier(provider: "anthropic", model: "claude-opus-4-7-20251101") == 6.0)
        #expect(ModelPricing.fastMultiplier(provider: "anthropic", model: "claude-opus-4-6") == 6.0)
        #expect(ModelPricing.fastMultiplier(provider: "anthropic", model: "claude-sonnet-4-6") == 1.0)
        #expect(ModelPricing.fastMultiplier(provider: "anthropic", model: "claude-opus-4-5") == 1.0)
        #expect(ModelPricing.fastMultiplier(provider: "openai", model: "gpt-5.5") == 1.0)
    }

    /// Fast mode scales the whole cost by the per-model multiplier.
    @Test func fastModeScalesEntireCost() {
        LiteLLMPricingCache.shared.clearForTesting()
        func cost(_ model: String, fast: Bool) -> Double? {
            ModelPricing.costUSD(
                provider: "anthropic", model: model,
                inputTokens: 1_000_000, outputTokens: 500_000, cacheReadTokens: 200_000,
                cacheWriteTokens: 100_000, reasoningTokens: 0,
                cacheWrite1hTokens: 40_000, fastMode: fast
            )
        }
        let opus48Std = try! #require(cost("claude-opus-4-8-20260101", fast: false))
        let opus48Fast = try! #require(cost("claude-opus-4-8-20260101", fast: true))
        #expect(abs(opus48Fast - opus48Std * 2.0) < 1e-9)

        let opus47Std = try! #require(cost("claude-opus-4-7-20251101", fast: false))
        let opus47Fast = try! #require(cost("claude-opus-4-7-20251101", fast: true))
        #expect(abs(opus47Fast - opus47Std * 6.0) < 1e-9)
    }
}

#if os(macOS)
@Suite("SidechainDedup")
struct SidechainDedupTests {

    private func field(msg: String?, req: String?, sidechain: Bool, input: Int) -> TokenUsageService.ParsedFields {
        TokenUsageService.ParsedFields(
            entry: UsageEntry(
                model: "claude-opus-4-8",
                tokens: TokenCount(inputTokens: input, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                fastMode: false
            ),
            messageId: msg,
            requestId: req,
            isSidechain: sidechain,
            fallbackId: "fb-\(msg ?? "x")-\(req ?? "x")-\(input)"
        )
    }

    /// A sidechain replay (same message id, fresh request id) collapses to one entry, keeping the original.
    @Test func sidechainReplayKeepsNonSidechain() {
        let parent = field(msg: "msg1", req: "req-parent", sidechain: false, input: 100)
        let replay = field(msg: "msg1", req: "req-sidechain", sidechain: true, input: 100)

        let result = TokenUsageService.deduplicate([parent, replay])
        #expect(result.count == 1)
        #expect(result[0].isSidechain == false)
    }

    /// Order-independent: even when the sidechain replay is seen first, the non-sidechain record wins.
    @Test func nonSidechainReplacesEarlierSidechain() {
        let replay = field(msg: "msg1", req: "req-sidechain", sidechain: true, input: 100)
        let parent = field(msg: "msg1", req: "req-parent", sidechain: false, input: 100)

        let result = TokenUsageService.deduplicate([replay, parent])
        #expect(result.count == 1)
        #expect(result[0].isSidechain == false)
    }

    /// Streaming writes the same id+requestId multiple times → collapses to one.
    @Test func streamingDuplicatesCollapse() {
        let a = field(msg: "msg1", req: "req1", sidechain: false, input: 100)
        let b = field(msg: "msg1", req: "req1", sidechain: false, input: 100)
        #expect(TokenUsageService.deduplicate([a, b]).count == 1)
    }

    /// On a tie of sidechain status, the higher-token (more complete) record is kept.
    @Test func higherTokenRecordWins() {
        let small = field(msg: "msg1", req: "req1", sidechain: false, input: 100)
        let large = field(msg: "msg1", req: "req1", sidechain: false, input: 300)
        let result = TokenUsageService.deduplicate([small, large])
        #expect(result.count == 1)
        #expect(result[0].entry.tokens.inputTokens == 300)
    }

    /// Entries missing ids cannot be deduped and are all retained.
    @Test func entriesWithoutIdsAreKept() {
        let a = field(msg: nil, req: nil, sidechain: false, input: 100)
        let b = field(msg: nil, req: nil, sidechain: false, input: 200)
        #expect(TokenUsageService.deduplicate([a, b]).count == 2)
    }
}
#endif
