//
//  DependencyContainer.swift
//  ClaudeMeter
//
//  Centralized dependency injection container for services
//

import Foundation
#if os(macOS)
import SwiftData
#endif

/// Centralized container for creating and managing dependencies
/// Provides platform-specific service initialization
enum DependencyContainer {
    // MARK: - Credential Services

    /// Create the platform-appropriate credential provider
    static func createCredentialProvider() -> any CredentialProvider {
        #if os(macOS)
        return MacOSCredentialService()
        #else
        return iOSCredentialService()
        #endif
    }

    // MARK: - API Services

    /// Create the Claude API service
    static func createAPIService() -> ClaudeAPIService {
        ClaudeAPIService()
    }

    // MARK: - Token Usage Services (macOS only)

    #if os(macOS)
    /// Create the token usage service for local JSONL log parsing.
    /// Auto-detects additional providers (Codex, OpenCode) by probing their data paths.
    static func createTokenUsageService() -> TokenUsageService {
        let fm = FileManager.default
        var sources: [any UsageLogSource] = []
        if Constants.codexSessionsDirectories.contains(where: { fm.fileExists(atPath: $0.path) }) {
            sources.append(CodexLogSource())
        }
        if Constants.openCodeDatabaseURLs.contains(where: { fm.fileExists(atPath: $0.path) }) {
            sources.append(OpenCodeLogSource())
        }
        return TokenUsageService(extraSources: sources)
    }

    /// Create the blog usage sync service for passive local usage ingestion
    static func createBlogUsageSyncService() -> BlogUsageSyncService {
        BlogUsageSyncService.shared
    }

    /// Create the Codex rate-limit window service, if Codex logs are present.
    static func createCodexUsageService() -> CodexUsageService? {
        let fm = FileManager.default
        guard Constants.codexSessionsDirectories.contains(where: { fm.fileExists(atPath: $0.path) }) else {
            return nil
        }
        return CodexUsageService()
    }

    /// Create the OpenCode Go dashboard quota service when dashboard auth is configured.
    static func createOpenCodeGoUsageService() -> OpenCodeGoUsageService? {
        guard OpenCodeGoUsageService.DashboardConfig.load() != nil else { return nil }
        return OpenCodeGoUsageService()
    }
    #endif

    // MARK: - ViewModel Factory

    #if os(macOS)
    /// Create the usage view model with all dependencies (macOS)
    /// - Parameter modelContext: SwiftData model context for token usage persistence
    /// - Returns: Configured UsageViewModel
    static func createUsageViewModel(modelContext: ModelContext) -> UsageViewModel {
        let credentialProvider = createCredentialProvider()
        let tokenService = createTokenUsageService()
        let blogUsageSyncService = createBlogUsageSyncService()
        let codexUsageService = createCodexUsageService()
        let openCodeGoUsageService = createOpenCodeGoUsageService()
        return UsageViewModel(
            credentialProvider: credentialProvider,
            tokenService: tokenService,
            blogUsageSyncService: blogUsageSyncService,
            codexUsageService: codexUsageService,
            openCodeGoUsageService: openCodeGoUsageService,
            modelContext: modelContext
        )
    }
    #else
    /// Create the usage view model with all dependencies (iOS)
    /// - Returns: Configured UsageViewModel
    static func createUsageViewModel() -> UsageViewModel {
        let credentialProvider = createCredentialProvider()
        return UsageViewModel(
            credentialProvider: credentialProvider
        )
    }
    #endif
}
