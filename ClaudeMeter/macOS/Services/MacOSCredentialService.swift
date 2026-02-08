//
//  MacOSCredentialService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import AppKit
import OSLog
internal import UniformTypeIdentifiers

/// macOS credential service that reads from Claude Code's Keychain entry,
/// falling back to ~/.claude/.credentials.json for older Claude CLI versions.
/// Syncs to ClaudeMeter's own Keychain for iOS access.
actor MacOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        // Try Claude Code's Keychain entry first (new location since ~Feb 2026)
        if let credentials = try? loadFromClaudeCodeKeychain() {
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

        // Fall back to file-based credentials
        Logger.credentials.debug("Claude Code Keychain not found, trying file")
        return try await loadFromFile()
    }

    /// Read credentials from Claude Code's Keychain entry
    private func loadFromClaudeCodeKeychain() throws -> ClaudeOAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.claudeCodeKeychainService,
            kSecAttrAccount as String: Constants.claudeCodeKeychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialError.keychainNotFound
        }

        let decoder = JSONDecoder()
        let file = try decoder.decode(CredentialsFile.self, from: data)

        guard let credentials = file.claudeAiOauth else {
            throw CredentialError.missingOAuth
        }

        return credentials
    }

    /// Read credentials from ~/.claude/.credentials.json (legacy)
    private func loadFromFile() async throws -> ClaudeOAuthCredentials {
        let fileURL = Constants.credentialsFileURL
        Logger.credentials.debug("Looking for credentials at: \(fileURL.path)")

        var data: Data?
        var accessError: Error?

        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CredentialError.fileNotFound
            }

            data = try Data(contentsOf: fileURL)
        } catch {
            accessError = error
            Logger.credentials.warning("Direct access failed: \(error.localizedDescription)")

            if let selectedData = await requestFileAccess() {
                data = selectedData
            } else {
                throw accessError ?? CredentialError.fileNotFound
            }
        }

        guard let credentialData = data else {
            throw CredentialError.fileNotFound
        }

        let decoder = JSONDecoder()
        let file = try decoder.decode(CredentialsFile.self, from: credentialData)

        guard let credentials = file.claudeAiOauth else {
            throw CredentialError.missingOAuth
        }

        if credentials.isExpired {
            throw CredentialError.expired
        }

        if !credentials.hasRequiredScope {
            throw CredentialError.missingScope
        }

        syncToKeychain(credentials)
        return credentials
    }

    private func syncToKeychain(_ credentials: ClaudeOAuthCredentials) {
        do {
            try KeychainHelper.saveCredentials(credentials)
            Logger.credentials.info("Synced credentials to iCloud Keychain")
        } catch {
            Logger.credentials.error("Failed to sync to Keychain: \(error.localizedDescription)")
        }
    }

    private func requestFileAccess() async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.message = "Please select the .credentials.json file from ~/.claude/"
                panel.allowedContentTypes = [.json]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")

                if panel.runModal() == .OK, let url = panel.url {
                    guard url.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: nil)
                        return
                    }

                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let data = try Data(contentsOf: url)
                        continuation.resume(returning: data)
                    } catch {
                        Logger.credentials.error("Failed to read selected file: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
#endif
