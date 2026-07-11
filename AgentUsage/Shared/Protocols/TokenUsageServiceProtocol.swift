//
//  TokenUsageServiceProtocol.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import AgentUsageKit

/// Protocol for fetching local token usage from JSONL logs
/// Enables dependency injection and testing with mock implementations
protocol TokenUsageServiceProtocol: Actor {
    /// Fetch aggregated token usage from local JSONL logs
    /// - Returns: Token usage snapshot with today, 30-day, and by-model breakdowns
    /// - Throws: TokenUsageError on failure
    func fetchUsage() async throws -> TokenUsageSnapshot

    /// Fetch parsed entries grouped by file for SwiftData import (incremental)
    /// - Parameter fileStates: Current file states for incremental reading
    /// - Returns: Dictionary of file URLs to incremental parse results
    /// - Throws: TokenUsageError on failure
    func fetchParsedEntries(
        fileStates: [String: TokenUsageService.FileState]
    ) async throws -> [URL: TokenUsageService.IncrementalParseResult]

    /// Fetch full detail for non-Claude providers discovered from local sources.
    func fetchExtraProviderDetails(since: Date) async -> [Provider: ProviderDetail]
}
#endif
