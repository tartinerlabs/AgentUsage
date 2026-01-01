//
//  KeychainHelper.swift
//  ClaudeMeter
//

import Foundation
import Security

/// Helper for iCloud Keychain credential storage and sync
enum KeychainHelper {
    static let service = "com.tartinerlabs.ClaudeMeter"
    static let account = "claude-oauth-credentials"

    /// Save credentials to iCloud Keychain (syncs across devices)
    static func saveCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item with iCloud sync enabled
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,  // Enable iCloud Keychain sync
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    /// Load credentials from iCloud Keychain
    static func loadCredentials() throws -> ClaudeOAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,  // Search both sync and non-sync items
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw CredentialError.keychainNotFound
            }
            throw CredentialError.keychainError(status)
        }

        guard let data = result as? Data else {
            throw CredentialError.invalidFormat
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ClaudeOAuthCredentials.self, from: data)
    }

    /// Delete credentials from Keychain
    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
