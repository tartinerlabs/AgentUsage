//
//  MacOSCredentialService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import OSLog
import Security

/// macOS credential service that reads from Claude Code's Keychain entry
/// via `/usr/bin/security` CLI (avoids repeated keychain access prompts).
actor MacOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let (credentials, rawData) = try loadFromClaudeCodeKeychain()
        Logger.credentials.debug("Loaded credentials from Claude Code Keychain")

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        // Refresh proactively (or on expiry) only when the user has opted in, since
        // Anthropic rotates refresh tokens and writing back can race Claude Code.
        if credentials.isExpired || credentials.isAboutToExpire {
            if autoRefreshEnabled, let refreshToken = credentials.refreshToken {
                do {
                    return try await refreshAndPersist(
                        current: credentials,
                        rawData: rawData,
                        refreshToken: refreshToken
                    )
                } catch {
                    Logger.credentials.error("Claude token auto-refresh failed: \(error.localizedDescription)")
                    // Fall through: surface expiry only if the token is actually expired.
                }
            }
            if credentials.isExpired {
                throw CredentialError.expired
            }
        }

        return credentials
    }

    private var autoRefreshEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.autoRefreshClaudeTokenKey)
    }

    // MARK: - Refresh + write-back

    /// Refreshes the token, writes the rotated credentials back to Claude Code's
    /// keychain entry (preserving any fields we don't model), and returns the result.
    private func refreshAndPersist(
        current: ClaudeOAuthCredentials,
        rawData: Data,
        refreshToken: String
    ) async throws -> ClaudeOAuthCredentials {
        let tokens = try await TokenRefreshService.shared.refresh(refreshToken: refreshToken)

        let expiresAtMs: Double? = tokens.expiresInSeconds.map {
            (Date().timeIntervalSince1970 + Double($0)) * 1000
        }
        let newRefreshToken = tokens.refreshToken ?? refreshToken
        let newScopes = tokens.scopes ?? current.scopes

        try writeBack(
            rawData: rawData,
            accessToken: tokens.accessToken,
            refreshToken: newRefreshToken,
            expiresAtMs: expiresAtMs,
            scopes: newScopes
        )
        Logger.credentials.info("Refreshed and persisted Claude token")

        return ClaudeOAuthCredentials(
            accessToken: tokens.accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAtMs ?? current.expiresAt,
            scopes: newScopes,
            subscriptionType: current.subscriptionType,
            rateLimitTier: current.rateLimitTier
        )
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
        guard let (_, written) = try? loadFromClaudeCodeKeychain(), written == Data(json.utf8) else {
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
    private func loadFromClaudeCodeKeychain() throws -> (credentials: ClaudeOAuthCredentials, rawData: Data) {
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
