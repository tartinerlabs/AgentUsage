//
//  APIServiceProtocol.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit

/// Protocol for fetching Claude API usage data
/// Enables dependency injection and testing with mock implementations
protocol APIServiceProtocol: Actor {
    /// Fetch current usage from the Claude API
    /// - Parameter token: OAuth access token
    /// - Returns: Usage snapshot with session, opus, and optional sonnet windows
    /// - Throws: APIError on failure
    func fetchUsage(token: String) async throws -> UsageSnapshot
}

#if os(macOS)
/// A provider-specific source of rate-limit windows.
///
/// Claude has its own cached `UsageSnapshot` path, while optional macOS
/// providers expose the provider-neutral representation directly.
protocol ProviderUsageServiceProtocol: Actor {
    func fetchSnapshot() async throws -> ProviderUsageSnapshot?
}
#endif
