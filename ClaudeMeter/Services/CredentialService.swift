//
//  CredentialService.swift
//  ClaudeMeter
//

import Foundation
import AppKit
internal import UniformTypeIdentifiers

actor CredentialService {
    enum CredentialError: LocalizedError {
        case fileNotFound
        case invalidFormat
        case missingOAuth
        case expired
        case missingScope

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
            }
        }
    }

    func loadCredentials() async throws -> ClaudeOAuthCredentials {
        let fileURL = Constants.credentialsFileURL
        print("[CredentialService] Looking for credentials at: \(fileURL.path)")
        
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
            print("[CredentialService] Direct access failed: \(error)")
            
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

        return credentials
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
                        print("[CredentialService] Failed to read selected file: \(error)")
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
