//
//  MacOSCredentialServiceTests.swift
//  AgentUsageTests
//

#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage

@Suite("macOS Credential Service")
struct MacOSCredentialServiceTests {
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
