#if os(macOS)
import Foundation
import Testing
@testable import AgentUsage

@Suite("macOS Credential Service")
struct MacOSCredentialServiceTests {
    @Test func readsLocalClaudeCodeCredentials() async throws {
        let expected = credentials()
        let service = MacOSCredentialService(claudeCodeKeychainLoader: { expected })
        let loaded = try await service.loadCredentials()
        #expect(loaded.accessToken == expected.accessToken)
    }

    @Test func missingLocalCredentialsFailsWithoutFallback() async {
        let service = MacOSCredentialService(claudeCodeKeychainLoader: {
            throw CredentialError.keychainNotFound
        })
        await #expect(throws: CredentialError.self) {
            try await service.loadCredentials()
        }
    }

    @Test func expiredLocalCredentialsAreNotRefreshed() async {
        let expired = credentials(expiresIn: -60)
        let service = MacOSCredentialService(claudeCodeKeychainLoader: { expired })
        do {
            _ = try await service.loadCredentials()
            Issue.record("Expected expired credential error")
        } catch CredentialError.expired {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func missingProfileScopeIsRejected() async {
        let invalid = credentials(scopes: ["user:inference"])
        let service = MacOSCredentialService(claudeCodeKeychainLoader: { invalid })
        do {
            _ = try await service.loadCredentials()
            Issue.record("Expected missing scope error")
        } catch CredentialError.missingScope {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func credentials(
        expiresIn: TimeInterval = 3_600,
        scopes: [String] = ["user:profile"]
    ) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(
            accessToken: "local-access-token",
            refreshToken: "local-refresh-token",
            expiresAt: Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1_000,
            scopes: scopes,
            subscriptionType: "max",
            rateLimitTier: nil
        )
    }
}
#endif
