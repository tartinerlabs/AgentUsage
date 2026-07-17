//
//  MacOSCredentialService.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import OSLog
import Security

enum ClaudeTokenRefreshPolicy {
    nonisolated static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Constants.autoRefreshClaudeTokenKey)
    }

    nonisolated static func shouldAttemptRefresh(
        for credentials: ClaudeOAuthCredentials,
        defaults: UserDefaults
    ) -> Bool {
        isEnabled(in: defaults)
            && credentials.refreshToken != nil
            && (credentials.isExpired || credentials.isAboutToExpire)
    }
}

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
    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        claudeCodeKeychainLoader: ClaudeCodeKeychainLoader? = nil,
        appKeychainLoader: AppKeychainLoader? = nil,
        appKeychainSaver: AppKeychainSaver? = nil
    ) {
        self.defaults = defaults
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

        // Refresh proactively (or on expiry) only when the user has opted in, since
        // Anthropic rotates refresh tokens and writing back can race Claude Code.
        if credentials.isExpired || credentials.isAboutToExpire {
            if ClaudeTokenRefreshPolicy.shouldAttemptRefresh(
                for: credentials,
                defaults: defaults
            ), let refreshToken = credentials.refreshToken {
                do {
                    let refreshed = try await refreshAndPersist(
                        source: source,
                        refreshToken: refreshToken
                    )
                    mirrorToSynchronizableKeychain(refreshed)
                    return refreshed
                } catch {
                    Logger.credentials.error("Claude token auto-refresh failed: \(error.localizedDescription)")
                    // Fall through: surface expiry only if the token is actually expired.
                }
            }
            if credentials.isExpired {
                throw CredentialError.expired
            }
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
        do {
            try appKeychainSaver(credentials)
            Logger.credentials.info("Mirrored Claude credentials to synchronizable Keychain")
        } catch {
            Logger.credentials.error("Failed to mirror Claude credentials to synchronizable Keychain: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh + write-back

    /// Refreshes the token, writes the rotated credentials back to the source
    /// credential store, and returns the result.
    private func refreshAndPersist(
        source: CredentialSource,
        refreshToken: String
    ) async throws -> ClaudeOAuthCredentials {
        let current = source.credentials
        let tokens = try await TokenRefreshService.shared.refresh(refreshToken: refreshToken)

        let expiresAtMs: Double? = tokens.expiresInSeconds.map {
            (Date().timeIntervalSince1970 + Double($0)) * 1000
        }
        let newRefreshToken = tokens.refreshToken ?? refreshToken
        let newScopes = tokens.scopes ?? current.scopes

        let refreshed = ClaudeOAuthCredentials(
            accessToken: tokens.accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAtMs ?? current.expiresAt,
            scopes: newScopes,
            subscriptionType: current.subscriptionType,
            rateLimitTier: current.rateLimitTier
        )

        switch source {
        case .claudeCode(_, let rawData):
            try writeBack(
                rawData: rawData,
                accessToken: refreshed.accessToken,
                refreshToken: newRefreshToken,
                expiresAtMs: expiresAtMs,
                scopes: newScopes
            )
        case .appKeychain:
            try appKeychainSaver(refreshed)
        }
        Logger.credentials.info("Refreshed and persisted Claude token")

        return refreshed
    }

    /// Mutates only the token fields of the raw keychain JSON and writes it back, so
    /// any keys Claude Code stores that we don't model are preserved verbatim.
    private func writeBack(
        rawData: Data,
        accessToken: String,
        refreshToken: String,
        expiresAtMs: Double?,
        scopes: [String]?
    ) throws {
        guard var root = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw CredentialError.invalidFormat
        }

        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        if let expiresAtMs { oauth["expiresAt"] = expiresAtMs }
        if let scopes { oauth["scopes"] = scopes }
        root["claudeAiOauth"] = oauth

        // Minified (single-line) JSON: `security -w` hex-encodes values containing
        // newlines, which corrupts the entry and breaks Claude Code.
        let minified = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let jsonString = String(data: minified, encoding: .utf8) else {
            throw CredentialError.invalidFormat
        }

        try saveToClaudeCodeKeychain(jsonString)
    }

    /// Writes the credentials JSON back via the Apple-signed `security` CLI so the
    /// keychain ACL stays stable (no per-launch prompts on an unsigned app). The
    /// secret is fed over stdin, never argv (which `ps` can read).
    private func saveToClaudeCodeKeychain(_ json: String) throws {
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let service = Constants.claudeCodeKeychainService
        let account = Constants.claudeCodeKeychainAccount
        let command = "add-generic-password -U -s \(service) -a \(account) -w \"\(escaped)\" -T /usr/bin/security\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(command.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        // `security -i` does not reliably surface failures via exit code, so verify
        // the write by reading the value back.
        guard let (_, written) = try? Self.loadFromClaudeCodeKeychain(), written == Data(json.utf8) else {
            let stderr = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderr.isEmpty ? "keychain write could not be verified" : stderr
            Logger.credentials.error("Claude token keychain write failed: \(message)")
            throw CredentialError.keychainError(errSecIO)
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
