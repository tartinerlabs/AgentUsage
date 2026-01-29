//
//  KeychainHelperTests.swift
//  ClaudeMeterTests
//
//  Tests for KeychainHelper credential storage
//

import Testing
import Foundation
@testable import ClaudeMeter

// MARK: - Credential Error Tests

@Suite("Credential Errors")
struct CredentialErrorTests {

    @Test func keychainNotFoundErrorDescription() {
        let error = CredentialError.keychainNotFound
        #expect(error.errorDescription?.lowercased().contains("not found") == true)
    }

    @Test func invalidFormatErrorDescription() {
        let error = CredentialError.invalidFormat
        #expect(error.errorDescription?.lowercased().contains("invalid") == true)
    }

    @Test func keychainErrorIncludesStatus() {
        let error = CredentialError.keychainError(-25300) // errSecItemNotFound
        let description = error.errorDescription ?? ""
        #expect(description.contains("-25300") || description.contains("Keychain"))
    }

    @Test func fileNotFoundErrorDescription() {
        let error = CredentialError.fileNotFound
        #expect(error.errorDescription?.lowercased().contains("not found") == true)
    }
}

// MARK: - OAuth Credentials Serialization Tests

@Suite("ClaudeOAuthCredentials Serialization")
struct ClaudeOAuthCredentialsSerializationTests {

    @Test func decodesValidCredentialsJSON() throws {
        let json = """
        {
            "accessToken": "test-token-123",
            "refreshToken": "refresh-456",
            "expiresAt": 1735689599000,
            "scopes": ["user:profile", "usage:read"],
            "subscriptionType": "pro",
            "rateLimitTier": "standard"
        }
        """

        let data = json.data(using: .utf8)!
        let credentials = try JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)

        #expect(credentials.accessToken == "test-token-123")
        #expect(credentials.refreshToken == "refresh-456")
        #expect(credentials.subscriptionType == "pro")
        #expect(credentials.scopes?.contains("user:profile") == true)
    }

    @Test func decodesMinimalCredentials() throws {
        let json = """
        {
            "accessToken": "minimal-token"
        }
        """

        let data = json.data(using: .utf8)!
        let credentials = try JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)

        #expect(credentials.accessToken == "minimal-token")
        #expect(credentials.refreshToken == nil)
        #expect(credentials.scopes == nil)
    }

    @Test func credentialsWithMaxPlanShowsMax() throws {
        let json = """
        {
            "accessToken": "token",
            "subscriptionType": "max"
        }
        """

        let data = json.data(using: .utf8)!
        let credentials = try JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)

        #expect(credentials.planDisplayName == "Max")
    }

    @Test func credentialsWithProPlanShowsPro() throws {
        let json = """
        {
            "accessToken": "token",
            "subscriptionType": "pro"
        }
        """

        let data = json.data(using: .utf8)!
        let credentials = try JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)

        #expect(credentials.planDisplayName == "Pro")
    }

    @Test func credentialsWithoutPlanShowsFree() throws {
        let json = """
        {
            "accessToken": "token"
        }
        """

        let data = json.data(using: .utf8)!
        let credentials = try JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)

        #expect(credentials.planDisplayName == "Free")
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let original = ClaudeOAuthCredentials(
            accessToken: "round-trip-token",
            refreshToken: "refresh",
            expiresAt: nil,
            scopes: ["test:scope"],
            subscriptionType: "pro",
            rateLimitTier: "standard"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeOAuthCredentials.self, from: data)

        #expect(decoded.accessToken == original.accessToken)
        #expect(decoded.refreshToken == original.refreshToken)
        #expect(decoded.subscriptionType == original.subscriptionType)
    }
}
