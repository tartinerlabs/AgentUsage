//
//  DependencyContainer.swift
//  AgentUsage
//
//  Centralized dependency injection container for services
//

import Foundation
import AgentUsageKit
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

    /// Create the macOS token import/query coordinator at the composition root.
    static func createTokenUsageCoordinator(modelContext: ModelContext) -> TokenUsageCoordinator {
        TokenUsageCoordinator(
            tokenService: createTokenUsageService(),
            modelContext: modelContext
        )
    }

    /// Create usage-history persistence backed by the app's SwiftData container.
    static func createUsageHistoryService(modelContext: ModelContext) -> UsageHistoryService {
        UsageHistoryService(
            repository: UsageHistoryRepository(modelContainer: modelContext.container)
        )
    }

    /// Create the blog usage sync service for passive local usage ingestion
    static func createBlogUsageSyncService() -> BlogUsageSyncService {
        BlogUsageSyncService.shared
    }

    /// Create the blog OAuth service for signing in to the blog usage-ingest endpoint.
    static func createBlogOAuthService() -> BlogOAuthService {
        BlogOAuthService.shared
    }

    /// Create rate-window services for optional macOS providers that have local
    /// credentials or data available.
    static func createProviderUsageServices() -> [Provider: any ProviderUsageServiceProtocol] {
        let fm = FileManager.default
        var services: [Provider: any ProviderUsageServiceProtocol] = [:]
        if Constants.codexAuthFileURLs.contains(where: { fm.fileExists(atPath: $0.path) }) {
            services[.codex] = CodexUsageService()
        }
        if Constants.openCodeDatabaseURLs.contains(where: { fm.fileExists(atPath: $0.path) }) {
            services[.openCode] = OpenCodeGoLocalUsageService()
        }
        return services
    }
    #endif

    // MARK: - ViewModel Factory

    #if os(macOS)
    /// Create the usage view model with all dependencies (macOS)
    /// - Parameter modelContext: SwiftData model context for token usage persistence
    /// - Returns: Configured UsageViewModel
    static func createUsageViewModel(modelContext: ModelContext) -> UsageViewModel {
        let credentialProvider = createCredentialProvider()
        let tokenUsageCoordinator = createTokenUsageCoordinator(modelContext: modelContext)
        let usageHistoryService = createUsageHistoryService(modelContext: modelContext)
        let blogUsageSyncService = createBlogUsageSyncService()
        let blogOAuthService = createBlogOAuthService()
        let providerUsageServices = createProviderUsageServices()
        return UsageViewModel(
            credentialProvider: credentialProvider,
            tokenUsageCoordinator: tokenUsageCoordinator,
            blogUsageSyncService: blogUsageSyncService,
            blogOAuthService: blogOAuthService,
            providerUsageServices: providerUsageServices,
            usageHistoryService: usageHistoryService
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
