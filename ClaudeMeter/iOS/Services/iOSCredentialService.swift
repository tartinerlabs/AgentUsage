//
//  iOSCredentialService.swift
//  ClaudeMeter
//

#if os(iOS)
import Foundation

/// iOS credential service that reads from Keychain
/// Credentials can be synced from macOS (when iCloud Keychain enabled) or entered manually
actor iOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        print("[iOSCredentialService] Loading credentials from Keychain")

        let credentials = try KeychainHelper.loadCredentials()

        if credentials.isExpired {
            throw CredentialError.expired
        }

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        return credentials
    }

    /// Save manually entered credentials to Keychain
    func saveCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        print("[iOSCredentialService] Saving manually entered credentials")
        try KeychainHelper.saveCredentials(credentials)
    }

    /// Parse JSON string and save credentials
    /// Accepts either full credentials.json format or just the claudeAiOauth object
    func saveCredentialsFromJSON(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw CredentialError.invalidFormat
        }

        let decoder = JSONDecoder()

        // Try parsing as full credentials file first
        if let credentialsFile = try? decoder.decode(CredentialsFile.self, from: data),
           let credentials = credentialsFile.claudeAiOauth {
            try saveCredentials(credentials)
            return
        }

        // Try parsing as direct ClaudeOAuthCredentials
        if let credentials = try? decoder.decode(ClaudeOAuthCredentials.self, from: data) {
            try saveCredentials(credentials)
            return
        }

        throw CredentialError.invalidFormat
    }

    /// Clear stored credentials
    func clearCredentials() {
        print("[iOSCredentialService] Clearing credentials")
        KeychainHelper.deleteCredentials()
    }
}
#endif
