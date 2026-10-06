//
//  KeychainHelper.swift
//  AgentUsage
//

import Foundation
import OSLog
import Security

/// Stores app-owned secrets. Provider OAuth credentials are never stored or synced here.
nonisolated enum KeychainHelper {
    nonisolated static let service = "com.tartinerlabs.AgentUsage"

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

    /// Remove the obsolete app-owned Claude credential copy, including iCloud Keychain copies.
    /// This query cannot match Claude Code or Claude Desktop's Keychain items.
    static func deleteLegacyClaudeCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "claude-oauth-credentials",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.keychain.error("Legacy Claude credential cleanup failed: \(status)")
        }
    }

    /// Save a generic UTF-8 secret string to Keychain.
    ///
    /// Uses the data-protection keychain, where access is governed by the
    /// `keychain-access-groups` entitlement rather than a per-item ACL. Items in
    /// the file-based login keychain carry an ACL whose *modification* is gated
    /// separately from read access and trusts no application, so any writer that
    /// touches the ACL prompts for the login password on every write.
    nonisolated static func saveString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue!
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    /// Load a generic UTF-8 secret string from Keychain.
    nonisolated static func loadString(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue!
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw CredentialError.keychainNotFound
            }
            throw CredentialError.keychainError(status)
        }

        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialError.invalidFormat
        }
        return value
    }

    /// Delete a generic Keychain string. Removes every match, not just the first.
    nonisolated static func deleteString(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue!
        ]
        SecItemDelete(query as CFDictionary)
    }
}
