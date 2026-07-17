//
//  ClaudeCredentialStore.swift
//  AgentUsageKit
//
//  Read-only access to the Claude OAuth access token stored in the shared
//  Keychain. Used by the widget extension so its timeline can fetch live usage
//  without the main app running.
//
//  The main app writes these credentials via `KeychainHelper` using the same
//  service/account and a synchronizable item in the team's default keychain
//  access group (`$(AppIdentifierPrefix)com.tartinerlabs.AgentUsage`). Any
//  target that reads them must share that access group.
//

import Foundation
import Security

/// Reads the Claude OAuth access token from the shared Keychain.
public enum ClaudeCredentialStore: Sendable {
    /// Keychain service — must match the main app's `KeychainHelper.service`.
    public static let service = "com.tartinerlabs.AgentUsage"
    /// Keychain account — must match the main app's `KeychainHelper.account`.
    public static let account = "claude-oauth-credentials"

    /// Minimal view of the stored credential JSON — only the fields needed to
    /// produce a usable bearer token.
    private struct StoredCredentials: Decodable {
        let accessToken: String
        let expiresAt: Double?  // milliseconds since epoch
        let scopes: [String]?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return Date(timeIntervalSince1970: expiresAt / 1000) < Date()
        }

        var hasRequiredScope: Bool {
            guard let scopes else { return true }
            return scopes.contains("user:profile")
        }
    }

    /// Load a valid access token, or nil if none is stored, it is expired, or it
    /// lacks the required scope.
    public static func loadAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // The app marks the item synchronizable; match either kind.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data),
              !credentials.isExpired,
              credentials.hasRequiredScope else {
            return nil
        }
        return credentials.accessToken
    }
}
