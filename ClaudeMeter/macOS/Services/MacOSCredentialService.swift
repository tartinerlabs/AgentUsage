//
//  MacOSCredentialService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import OSLog

/// macOS credential service that reads from Claude Code's Keychain entry
/// via `/usr/bin/security` CLI (avoids repeated keychain access prompts).
/// Syncs to ClaudeMeter's own Keychain for iOS access.
actor MacOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let credentials = try loadFromClaudeCodeKeychain()
        Logger.credentials.debug("Loaded credentials from Claude Code Keychain")

        if credentials.isExpired {
            throw CredentialError.expired
        }

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        syncToKeychain(credentials)
        return credentials
    }

    /// Read credentials from Claude Code's Keychain entry using `/usr/bin/security` CLI.
    /// This avoids the repeated "wants to access key" prompts that `SecItemCopyMatching`
    /// triggers when reading another app's keychain item, because the `security` binary
    /// has a stable code signature so "Always Allow" persists across app rebuilds.
    private func loadFromClaudeCodeKeychain() throws -> ClaudeOAuthCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", Constants.claudeCodeKeychainService,
            "-a", Constants.claudeCodeKeychainAccount,
            "-w"  // output password data only
        ]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Logger.credentials.error("Failed to run security CLI: \(error.localizedDescription)")
            throw CredentialError.keychainNotFound
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "unknown error"
            Logger.credentials.debug("security CLI failed (\(process.terminationStatus)): \(errorMessage)")
            throw CredentialError.keychainNotFound
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let jsonString = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !jsonString.isEmpty else {
            throw CredentialError.keychainNotFound
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw CredentialError.invalidFormat
        }

        let decoder = JSONDecoder()
        let file = try decoder.decode(CredentialsFile.self, from: data)

        guard let credentials = file.claudeAiOauth else {
            throw CredentialError.missingOAuth
        }

        return credentials
    }

    private func syncToKeychain(_ credentials: ClaudeOAuthCredentials) {
        do {
            try KeychainHelper.saveCredentials(credentials)
            Logger.credentials.info("Synced credentials to ClaudeMeter Keychain")
        } catch {
            Logger.credentials.error("Failed to sync to Keychain: \(error.localizedDescription)")
        }
    }
}
#endif
