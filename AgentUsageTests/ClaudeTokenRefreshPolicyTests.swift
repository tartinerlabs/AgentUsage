//
//  ClaudeTokenRefreshPolicyTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage

@Suite("Claude Token Refresh Policy")
struct ClaudeTokenRefreshPolicyTests {
    @Test func missingPreferenceDefaultsToDisabled() {
        let testDefaults = TestUserDefaults()
        let credentials = credentials(expiresIn: -3_600, refreshToken: "refresh-token")

        #expect(ClaudeTokenRefreshPolicy.isEnabled(in: testDefaults.defaults) == false)
        #expect(
            ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials,
                defaults: testDefaults.defaults
            ) == false
        )
    }

    @Test func disabledPreferenceSkipsNearlyExpiredCredentials() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(false, forKey: Constants.autoRefreshClaudeTokenKey)
        let credentials = credentials(expiresIn: 120, refreshToken: "refresh-token")

        #expect(
            ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials,
                defaults: testDefaults.defaults
            ) == false
        )
    }

    @Test func existingOptInAllowsExpiredAndNearlyExpiredCredentials() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: Constants.autoRefreshClaudeTokenKey)

        #expect(ClaudeTokenRefreshPolicy.isEnabled(in: testDefaults.defaults))
        #expect(
            ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials(expiresIn: -3_600, refreshToken: "refresh-token"),
                defaults: testDefaults.defaults
            )
        )
        #expect(
            ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials(expiresIn: 120, refreshToken: "refresh-token"),
                defaults: testDefaults.defaults
            )
        )
    }

    @Test func enabledPreferenceStillRequiresRefreshToken() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: Constants.autoRefreshClaudeTokenKey)

        #expect(
            ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials(expiresIn: -3_600, refreshToken: nil),
                defaults: testDefaults.defaults
            ) == false
        )
    }

    private func credentials(
        expiresIn interval: TimeInterval,
        refreshToken: String?
    ) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(
            accessToken: "access-token",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(interval).timeIntervalSince1970 * 1_000,
            scopes: ["user:profile"],
            subscriptionType: "max",
            rateLimitTier: nil
        )
    }
}
#endif
