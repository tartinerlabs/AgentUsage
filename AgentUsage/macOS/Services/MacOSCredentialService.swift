//
//  MacOSCredentialService.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import OSLog
import Security

/// macOS credential service that reads from Claude Code's Keychain entry
/// via `/usr/bin/security` CLI (avoids repeated keychain access prompts).
actor MacOSCredentialService: CredentialProvider {
    typealias ClaudeCodeKeychainLoader = () throws -> ClaudeOAuthCredentials

    private let claudeCodeKeychainLoader: ClaudeCodeKeychainLoader

    init(claudeCodeKeychainLoader: ClaudeCodeKeychainLoader? = nil) {
        self.claudeCodeKeychainLoader = claudeCodeKeychainLoader ?? Self.loadFromClaudeCodeKeychain
    }

    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let credentials = try claudeCodeKeychainLoader()

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        // Claude Code owns the credential lifecycle: an expired token is refreshed by
        // running `claude`, not by this read-only viewer.
        if credentials.isExpired {
            throw CredentialError.expired
        }

        return credentials
    }

    // MARK: - Keychain read

    /// Read credentials from Claude Code's Keychain entry using `/usr/bin/security` CLI.
    /// This avoids the repeated "wants to access key" prompts that `SecItemCopyMatching`
    /// triggers when reading another app's keychain item, because the `security` binary
    /// has a stable code signature so "Always Allow" persists across app rebuilds.
    ///
    /// Reads only Claude Code's local credential; never refreshes, mirrors, or writes it.
    private static func loadFromClaudeCodeKeychain() throws -> ClaudeOAuthCredentials {
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
}
#endif
