//
//  CredentialProvider.swift
//  ClaudeMeter
//

import Foundation

/// Protocol for loading Claude OAuth credentials across platforms
protocol CredentialProvider: Actor {
    func loadCredentials() async throws -> ClaudeOAuthCredentials
}

/// Errors related to credential loading
enum CredentialError: LocalizedError {
    case fileNotFound
    case invalidFormat
    case missingOAuth
    case expired
    case missingScope
    case keychainNotFound
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Credentials not found. Please run 'claude' CLI first to authenticate."
        case .invalidFormat:
            return "Invalid credentials format."
        case .missingOAuth:
            return "No OAuth credentials found. Please authenticate with Claude CLI."
        case .expired:
            return "Credentials have expired. Please re-authenticate with Claude CLI."
        case .missingScope:
            return "Missing required 'user:profile' scope."
        case .keychainNotFound:
            #if os(iOS)
            return "Credentials not synced. Please open ClaudeMeter on your Mac first."
            #else
            return "Credentials not found in Keychain."
            #endif
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
