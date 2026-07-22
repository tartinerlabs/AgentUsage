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
    ///
    /// Codex sources are attached unconditionally: each no-ops when its data path
    /// is absent or the user has not yet granted sandbox access, so there is no
    /// launch-time `fileExists` probe.
    static func createTokenUsageService(defaults: UserDefaults = .standard) -> TokenUsageService {
        let sources: [any UsageLogSource] = [
            CodexLogSource(),
            // OpenCodeLogSource(), // Disabled: OpenCode usage is currently unreliable.
        ]
        return TokenUsageService(extraSources: sources)
    }

    /// Create the macOS token import/query coordinator at the composition root.
    static func createTokenUsageCoordinator(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) -> TokenUsageCoordinator {
        TokenUsageCoordinator(
            tokenService: createTokenUsageService(defaults: defaults),
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

    /// Create rate-window services for optional macOS providers.
    ///
    /// Attached unconditionally for the same reason as `createTokenUsageService`: each
    /// service no-ops without local credentials/data or sandbox access, and the
    /// `UsageViewModel` decides what to surface from whether data actually comes back.
    static func createProviderUsageServices(defaults: UserDefaults = .standard) -> [Provider: any ProviderUsageServiceProtocol] {
        [
            .codex: CodexUsageService(),
            // .openCodeGo: OpenCodeGoLocalUsageService(), // Disabled: OpenCode usage is currently unreliable.
        ]
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
            usageHistoryService: usageHistoryService,
            usageSyncService: UsageSyncService.shared
        )
    }
    #else
    /// Create the usage view model with all dependencies (iOS)
    /// - Returns: Configured UsageViewModel
    static func createUsageViewModel() -> UsageViewModel {
        let credentialProvider = createCredentialProvider()
        return UsageViewModel(
            credentialProvider: credentialProvider,
            usageSyncService: UsageSyncService.shared
        )
    }
    #endif
}
