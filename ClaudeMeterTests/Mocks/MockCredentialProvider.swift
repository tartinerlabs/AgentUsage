//
//  MockCredentialProvider.swift
//  ClaudeMeterTests
//
//  Mock implementation of CredentialProvider for testing
//

import Foundation
@testable import ClaudeMeter

/// Mock credential provider for testing
actor MockCredentialProvider: CredentialProvider {
    /// Configurable credentials to return
    var mockCredentials: ClaudeOAuthCredentials?

    /// Configurable error to throw
    var mockError: Error?

    /// Track number of load calls
    private(set) var loadCallCount = 0

    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        loadCallCount += 1

        if let error = mockError {
            throw error
        }

        guard let credentials = mockCredentials else {
            throw CredentialError.fileNotFound
        }

        return credentials
    }

    /// Reset mock state
    func reset() {
        mockCredentials = nil
        mockError = nil
        loadCallCount = 0
    }

    /// Create valid test credentials
    static func validCredentials(
        accessToken: String = "test-token",
        expiresInHours: Int = 24,
        subscriptionType: String = "pro"
    ) -> ClaudeOAuthCredentials {
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresInHours * 3600)).timeIntervalSince1970 * 1000
        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: nil,
            expiresAt: expiresAt,
            scopes: ["user:profile"],
            subscriptionType: subscriptionType,
            rateLimitTier: nil
        )
    }

    /// Create expired test credentials
    static func expiredCredentials() -> ClaudeOAuthCredentials {
        let expiresAt = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        return ClaudeOAuthCredentials(
            accessToken: "expired-token",
            refreshToken: nil,
            expiresAt: expiresAt,
            scopes: ["user:profile"],
            subscriptionType: "pro",
            rateLimitTier: nil
        )
    }
}
