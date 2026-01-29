//
//  NetworkRetryTests.swift
//  ClaudeMeterTests
//
//  Tests for network retry logic and error handling
//

import Testing
import Foundation
@testable import ClaudeMeter

// MARK: - API Error Retry Tests

@Suite("API Error Retryability")
struct APIErrorRetryTests {

    @Test func networkErrorIsRetryable() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let error = ClaudeAPIService.APIError.networkError(underlying)
        #expect(error.isRetryable == true)
    }

    @Test func rateLimitedIsRetryable() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: 60)
        #expect(error.isRetryable == true)
    }

    @Test func rateLimitedWithoutRetryAfterIsRetryable() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: nil)
        #expect(error.isRetryable == true)
    }

    @Test func serviceUnavailableIsRetryable() {
        let error = ClaudeAPIService.APIError.serviceUnavailable
        #expect(error.isRetryable == true)
    }

    @Test func serverError500IsRetryable() {
        let error = ClaudeAPIService.APIError.serverError(500)
        #expect(error.isRetryable == true)
    }

    @Test func serverError502IsRetryable() {
        let error = ClaudeAPIService.APIError.serverError(502)
        #expect(error.isRetryable == true)
    }

    @Test func serverError503IsRetryable() {
        let error = ClaudeAPIService.APIError.serverError(503)
        #expect(error.isRetryable == true)
    }

    @Test func serverError501NotImplementedIsNotRetryable() {
        // 501 Not Implemented means the server doesn't support this,
        // so retrying won't help
        let error = ClaudeAPIService.APIError.serverError(501)
        #expect(error.isRetryable == false)
    }

    @Test func serverError400IsNotRetryable() {
        let error = ClaudeAPIService.APIError.serverError(400)
        #expect(error.isRetryable == false)
    }

    @Test func serverError404IsNotRetryable() {
        let error = ClaudeAPIService.APIError.serverError(404)
        #expect(error.isRetryable == false)
    }

    @Test func unauthorizedIsNotRetryable() {
        let error = ClaudeAPIService.APIError.unauthorized
        #expect(error.isRetryable == false)
    }

    @Test func invalidResponseIsNotRetryable() {
        let error = ClaudeAPIService.APIError.invalidResponse
        #expect(error.isRetryable == false)
    }

    @Test func maxRetriesExceededIsNotRetryable() {
        let error = ClaudeAPIService.APIError.maxRetriesExceeded
        #expect(error.isRetryable == false)
    }
}

// MARK: - API Error Description Tests

@Suite("API Error Descriptions")
struct APIErrorDescriptionTests {

    @Test func rateLimitedWithRetryAfterDescription() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: 60)
        #expect(error.errorDescription?.contains("60 seconds") == true)
    }

    @Test func rateLimitedWithoutRetryAfterDescription() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: nil)
        #expect(error.errorDescription?.contains("Rate limited") == true)
        #expect(error.errorDescription?.contains("try again later") == true)
    }

    @Test func serviceUnavailableDescription() {
        let error = ClaudeAPIService.APIError.serviceUnavailable
        #expect(error.errorDescription?.contains("temporarily unavailable") == true)
    }

    @Test func maxRetriesExceededDescription() {
        let error = ClaudeAPIService.APIError.maxRetriesExceeded
        #expect(error.errorDescription?.contains("retry") == true)
    }
}

// MARK: - Constants Tests

@Suite("Network Constants")
struct NetworkConstantsTests {

    @Test func requestTimeoutIsReasonable() {
        // Timeout should be between 10 and 120 seconds
        #expect(Constants.requestTimeout >= 10)
        #expect(Constants.requestTimeout <= 120)
    }

    @Test func maxRetryAttemptsIsReasonable() {
        // Should have at least 2 attempts but not more than 5
        #expect(Constants.maxRetryAttempts >= 2)
        #expect(Constants.maxRetryAttempts <= 5)
    }

    @Test func initialRetryDelayIsReasonable() {
        // Initial delay should be between 0.5 and 5 seconds
        #expect(Constants.initialRetryDelay >= 0.5)
        #expect(Constants.initialRetryDelay <= 5.0)
    }

    @Test func retryBackoffMultiplierIsReasonable() {
        // Multiplier should be between 1.5 and 3
        #expect(Constants.retryBackoffMultiplier >= 1.5)
        #expect(Constants.retryBackoffMultiplier <= 3.0)
    }

    @Test func exponentialBackoffCalculation() {
        // Verify backoff grows as expected
        let initial = Constants.initialRetryDelay
        let multiplier = Constants.retryBackoffMultiplier

        let delay0 = initial * pow(multiplier, 0) // First attempt: 1s
        let delay1 = initial * pow(multiplier, 1) // Second attempt: 2s
        let delay2 = initial * pow(multiplier, 2) // Third attempt: 4s

        #expect(delay0 == initial)
        #expect(delay1 > delay0)
        #expect(delay2 > delay1)
        #expect(delay2 == delay0 * multiplier * multiplier)
    }
}
