//
//  MockAPIService.swift
//  ClaudeMeterTests
//
//  Mock implementation of APIServiceProtocol for testing
//

import Foundation
@testable import ClaudeMeter
import ClaudeMeterKit

/// Mock API service for testing
actor MockAPIService: APIServiceProtocol {
    /// Configurable response to return on fetch
    var mockSnapshot: UsageSnapshot?

    /// Configurable error to throw on fetch
    var mockError: Error?

    /// Track number of fetch calls
    private(set) var fetchCallCount = 0

    /// Track tokens passed to fetch
    private(set) var lastFetchToken: String?

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        fetchCallCount += 1
        lastFetchToken = token

        if let error = mockError {
            throw error
        }

        guard let snapshot = mockSnapshot else {
            throw ClaudeAPIService.APIError.invalidResponse
        }

        return snapshot
    }

    /// Reset mock state
    func reset() {
        mockSnapshot = nil
        mockError = nil
        fetchCallCount = 0
        lastFetchToken = nil
    }
}
