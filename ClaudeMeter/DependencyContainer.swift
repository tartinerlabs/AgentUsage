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
    /// Create the token usage service for local JSONL log parsing
    static func createTokenUsageService() -> TokenUsageService {
        TokenUsageService()
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
        return UsageViewModel(
            credentialProvider: credentialProvider,
            tokenService: tokenService,
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
