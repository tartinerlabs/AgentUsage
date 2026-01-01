//
//  iOSCredentialService.swift
//  ClaudeMeter
//

#if os(iOS)
import Foundation

/// iOS credential service that reads from iCloud Keychain
/// Credentials are synced from macOS app
actor iOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        print("[iOSCredentialService] Loading credentials from iCloud Keychain")

        let credentials = try KeychainHelper.loadCredentials()

        if credentials.isExpired {
            throw CredentialError.expired
        }

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        return credentials
    }
}
#endif
