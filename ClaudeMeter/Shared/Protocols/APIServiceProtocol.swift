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
