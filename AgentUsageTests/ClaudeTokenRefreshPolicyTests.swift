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

    @Test func macOSCredentialServiceFallsBackToAppKeychain() async throws {
        let fallbackCredentials = credentials(
            accessToken: "fallback-token",
            expiresIn: 3_600,
            refreshToken: nil
        )
        var mirroredCredentials: ClaudeOAuthCredentials?
        let service = MacOSCredentialService(
            claudeCodeKeychainLoader: {
                throw CredentialError.keychainNotFound
            },
            appKeychainLoader: {
                fallbackCredentials
            },
            appKeychainSaver: { credentials in
                mirroredCredentials = credentials
            }
        )

        let loaded = try await service.loadCredentials()

        #expect(loaded.accessToken == "fallback-token")
        #expect(mirroredCredentials?.accessToken == "fallback-token")
    }

    @Test func macOSCredentialServicePrefersClaudeCodeKeychain() async throws {
        let claudeCodeCredentials = credentials(
            accessToken: "claude-code-token",
            expiresIn: 3_600,
            refreshToken: nil
        )
        let fallbackCredentials = credentials(
            accessToken: "fallback-token",
            expiresIn: 3_600,
            refreshToken: nil
        )
        var mirroredCredentials: ClaudeOAuthCredentials?
        let service = MacOSCredentialService(
            claudeCodeKeychainLoader: {
                (claudeCodeCredentials, Data(#"{"claudeAiOauth":{"accessToken":"claude-code-token"}}"#.utf8))
            },
            appKeychainLoader: {
                fallbackCredentials
            },
            appKeychainSaver: { credentials in
                mirroredCredentials = credentials
            }
        )

        let loaded = try await service.loadCredentials()

        #expect(loaded.accessToken == "claude-code-token")
        #expect(mirroredCredentials?.accessToken == "claude-code-token")
    }

    @Test func macOSCredentialServiceValidatesFallbackCredentials() async {
        let invalidCredentials = ClaudeOAuthCredentials(
            accessToken: "fallback-token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3_600).timeIntervalSince1970 * 1_000,
            scopes: ["other:scope"],
            subscriptionType: "max",
            rateLimitTier: nil
        )
        let service = MacOSCredentialService(
            claudeCodeKeychainLoader: {
                throw CredentialError.keychainNotFound
            },
            appKeychainLoader: {
                invalidCredentials
            },
            appKeychainSaver: { _ in }
        )

        do {
            _ = try await service.loadCredentials()
            Issue.record("Expected missing scope error")
        } catch CredentialError.missingScope {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func credentials(
        accessToken: String = "access-token",
        expiresIn interval: TimeInterval,
        refreshToken: String?
    ) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(interval).timeIntervalSince1970 * 1_000,
            scopes: ["user:profile"],
            subscriptionType: "max",
            rateLimitTier: nil
        )
    }
}
#endif
