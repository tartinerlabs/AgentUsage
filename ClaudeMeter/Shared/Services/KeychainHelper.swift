//
//  KeychainHelper.swift
//  ClaudeMeter
//

import Foundation
import OSLog
import Security

/// Helper for Keychain credential storage
/// TODO: Enable iCloud Keychain sync when paid developer account is available
enum KeychainHelper {
    static let service = "com.tartinerlabs.ClaudeMeter"
    static let account = "claude-oauth-credentials"

    /// Get human-readable description for an OSStatus code
    static func describeStatus(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found in keychain"
        case errSecDuplicateItem:
            return "Item already exists in keychain"
        case errSecAuthFailed:
            return "Authentication failed - check keychain access"
        case errSecInteractionNotAllowed:
            return "User interaction required - unlock device"
        case errSecDecode:
            return "Unable to decode keychain data"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failed"
        case errSecNotAvailable:
            return "Keychain not available"
        case errSecReadOnly:
            return "Keychain is read-only"
        case errSecNoSuchKeychain:
            return "Keychain does not exist"
        case errSecDataTooLarge:
            return "Data too large for keychain"
        case errSecNoDefaultKeychain:
            return "No default keychain"
        case errSecInteractionRequired:
            return "User interaction required"
        case errSecDataNotAvailable:
            return "Data not available"
        case errSecMissingEntitlement:
            return "Missing entitlement"
        case -34018: // errSecMissingEntitlement on some systems
            return "Missing entitlement - check app signing"
        default:
            if let message = SecCopyErrorMessageString(status, nil) as? String {
                return message
            }
            return "Unknown keychain error (code: \(status))"
        }
    }

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
        Logger.keychain.debug("Delete existing: \(deleteStatus)")

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
        if status == errSecSuccess {
            Logger.keychain.debug("Save credentials: success")
        } else {
            Logger.keychain.error("Save credentials failed: \(status)")
        }

        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }

        Logger.keychain.info("Credentials saved to Keychain successfully")
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

        if status == errSecSuccess {
            Logger.keychain.debug("Load credentials: success")
        } else if status == errSecItemNotFound {
            Logger.keychain.debug("Load credentials: not found")
        } else {
            Logger.keychain.error("Load credentials failed: \(status)")
        }

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
        Logger.keychain.info("Credentials loaded successfully")
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
