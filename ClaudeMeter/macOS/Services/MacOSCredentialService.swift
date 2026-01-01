//
//  MacOSCredentialService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import AppKit
internal import UniformTypeIdentifiers

/// macOS credential service that reads from ~/.claude/.credentials.json
/// and syncs to iCloud Keychain for iOS access
actor MacOSCredentialService: CredentialProvider {
    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let fileURL = Constants.credentialsFileURL
        print("[MacOSCredentialService] Looking for credentials at: \(fileURL.path)")

        // Try to access the file directly first
        var data: Data?
        var accessError: Error?

        do {
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CredentialError.fileNotFound
            }

            // Try to read with bookmark or direct access
            data = try Data(contentsOf: fileURL)
        } catch {
            accessError = error
            print("[MacOSCredentialService] Direct access failed: \(error)")

            // If sandboxed and access fails, prompt user to select the file
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

        // Sync to iCloud Keychain for iOS access
        syncToKeychain(credentials)

        return credentials
    }

    private func syncToKeychain(_ credentials: ClaudeOAuthCredentials) {
        do {
            try KeychainHelper.saveCredentials(credentials)
            print("[MacOSCredentialService] Synced credentials to iCloud Keychain")
        } catch {
            print("[MacOSCredentialService] Failed to sync to Keychain: \(error)")
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
                    // Start accessing security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: nil)
                        return
                    }

                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let data = try Data(contentsOf: url)
                        continuation.resume(returning: data)
                    } catch {
                        print("[MacOSCredentialService] Failed to read selected file: \(error)")
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
