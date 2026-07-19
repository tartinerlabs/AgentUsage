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
    typealias ClaudeCodeKeychainLoader = () throws -> (credentials: ClaudeOAuthCredentials, rawData: Data)
    typealias AppKeychainLoader = () throws -> ClaudeOAuthCredentials
    typealias AppKeychainSaver = (ClaudeOAuthCredentials) throws -> Void

    private enum CredentialSource {
        case claudeCode(credentials: ClaudeOAuthCredentials, rawData: Data)
        case appKeychain(credentials: ClaudeOAuthCredentials)

        var credentials: ClaudeOAuthCredentials {
            switch self {
            case .claudeCode(let credentials, _), .appKeychain(let credentials):
                return credentials
            }
        }
    }

    private let claudeCodeKeychainLoader: ClaudeCodeKeychainLoader
    private let appKeychainLoader: AppKeychainLoader
    private let appKeychainSaver: AppKeychainSaver

    init(
        claudeCodeKeychainLoader: ClaudeCodeKeychainLoader? = nil,
        appKeychainLoader: AppKeychainLoader? = nil,
        appKeychainSaver: AppKeychainSaver? = nil
    ) {
        self.claudeCodeKeychainLoader = claudeCodeKeychainLoader ?? Self.loadFromClaudeCodeKeychain
        self.appKeychainLoader = appKeychainLoader ?? { try KeychainHelper.loadCredentials() }
        self.appKeychainSaver = appKeychainSaver ?? { try KeychainHelper.saveCredentials($0) }
    }

    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let source = try loadCredentialSource()
        let credentials = source.credentials

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        // Claude Code owns the credential lifecycle: an expired token is refreshed by
        // running `claude`, not by this read-only viewer.
        if credentials.isExpired {
            throw CredentialError.expired
        }

        mirrorToSynchronizableKeychain(credentials)
        return credentials
    }

    private func loadCredentialSource() throws -> CredentialSource {
        do {
            let (credentials, rawData) = try claudeCodeKeychainLoader()
            Logger.credentials.debug("Loaded credentials from Claude Code Keychain")
            return .claudeCode(credentials: credentials, rawData: rawData)
        } catch {
            Logger.credentials.debug("Claude Code Keychain unavailable, trying AgentUsage Keychain: \(error.localizedDescription)")
        }

        let credentials = try appKeychainLoader()
        Logger.credentials.debug("Loaded credentials from AgentUsage Keychain")
        return .appKeychain(credentials: credentials)
    }

    /// Seed AgentUsage's own synchronizable Keychain item from Claude Code's
    /// credential so iOS can receive it through iCloud Keychain.
    private func mirrorToSynchronizableKeychain(_ credentials: ClaudeOAuthCredentials) {
        guard !UserDefaults.standard.bool(forKey: Constants.continuitySyncRevokedKey) else {
            Logger.credentials.debug("Continuity Sync is off; skipping synchronizable Keychain mirror")
            return
        }

        do {
            try appKeychainSaver(credentials)
            Logger.credentials.info("Mirrored Claude credentials to synchronizable Keychain")
        } catch {
            Logger.credentials.error("Failed to mirror Claude credentials to synchronizable Keychain: \(error.localizedDescription)")
        }
    }

    // MARK: - Keychain read

    /// Read credentials from Claude Code's Keychain entry using `/usr/bin/security` CLI.
    /// This avoids the repeated "wants to access key" prompts that `SecItemCopyMatching`
    /// triggers when reading another app's keychain item, because the `security` binary
    /// has a stable code signature so "Always Allow" persists across app rebuilds.
    ///
    /// Returns the decoded credentials plus the raw JSON bytes (needed to round-trip a
    /// write-back without dropping fields we don't model).
    private static func loadFromClaudeCodeKeychain() throws -> (credentials: ClaudeOAuthCredentials, rawData: Data) {
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

        return (credentials, data)
    }
}
#endif
