//
//  KeychainHelper.swift
//  ClaudeMeter
//

import Foundation
import Security

/// Helper for Keychain credential storage
/// TODO: Enable iCloud Keychain sync when paid developer account is available
enum KeychainHelper {
    static let service = "com.tartinerlabs.ClaudeMeter"
    static let account = "claude-oauth-credentials"

    /// Save credentials to Keychain
    static func saveCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
            // TODO: Uncomment for iCloud sync (requires paid developer account)
            // kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        print("[KeychainHelper] Delete existing: \(deleteStatus)")

        // Add new item to Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            // TODO: Uncomment for iCloud sync (requires paid developer account)
            // kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        print("[KeychainHelper] Save credentials: \(status) (\(status == errSecSuccess ? "success" : "error: \(status)"))")

        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }

        print("[KeychainHelper] Credentials saved to Keychain successfully")
    }

    /// Load credentials from Keychain
    static func loadCredentials() throws -> ClaudeOAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
            // TODO: Uncomment for iCloud sync (requires paid developer account)
            // kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        print("[KeychainHelper] Load credentials: \(status) (\(status == errSecSuccess ? "success" : status == errSecItemNotFound ? "not found" : "error: \(status)"))")

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
        let credentials = try decoder.decode(ClaudeOAuthCredentials.self, from: data)
        print("[KeychainHelper] Credentials loaded successfully")
        return credentials
    }

    /// Delete credentials from Keychain
    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
            // TODO: Uncomment for iCloud sync (requires paid developer account)
            // kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
