//
//  MockAPIService.swift
//  AgentUsageTests
//
//  Mock implementation of APIServiceProtocol for testing
//

import Foundation
@testable import AgentUsage
import AgentUsageKit

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

    /// Configure the snapshot returned on the next fetch.
    func setMockSnapshot(_ snapshot: UsageSnapshot?) {
        mockSnapshot = snapshot
    }

    /// Configure the error thrown on the next fetch (nil to fetch successfully).
    func setMockError(_ error: Error?) {
        mockError = error
    }

    /// Reset mock state
    func reset() {
        mockSnapshot = nil
        mockError = nil
        fetchCallCount = 0
        lastFetchToken = nil
    }
}
