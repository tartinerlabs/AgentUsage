//
//  OutageTrackingTests.swift
//  ClaudeMeterTests
//
//  Tests for Claude API outage detection, incident lifecycle, and regression safety
//

import Testing
import Foundation
@testable import ClaudeMeter
@testable import ClaudeMeterKit

// MARK: - Outage Classification Tests

@Suite("Outage Error Classification")
struct OutageClassificationTests {

    @Test func serviceUnavailableIsOutage() {
        let error = ClaudeAPIService.APIError.serviceUnavailable
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError500IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(500)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError502IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(502)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError503IsOutage() {
        let error = ClaudeAPIService.APIError.serverError(503)
        #expect(UsageViewModel.isOutageError(error) == true)
    }

    @Test func serverError400IsNotOutage() {
        let error = ClaudeAPIService.APIError.serverError(400)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func serverError404IsNotOutage() {
        let error = ClaudeAPIService.APIError.serverError(404)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func networkErrorIsNotOutage() {
        let error = ClaudeAPIService.APIError.networkError(URLError(.notConnectedToInternet))
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func rateLimitedIsNotOutage() {
        let error = ClaudeAPIService.APIError.rateLimited(retryAfter: 30)
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func unauthorizedIsNotOutage() {
        let error = ClaudeAPIService.APIError.unauthorized
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func invalidResponseIsNotOutage() {
        let error = ClaudeAPIService.APIError.invalidResponse
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func maxRetriesExceededIsNotOutage() {
        let error = ClaudeAPIService.APIError.maxRetriesExceeded
        #expect(UsageViewModel.isOutageError(error) == false)
    }

    @Test func nonAPIErrorIsNotOutage() {
        let error = URLError(.timedOut)
        #expect(UsageViewModel.isOutageError(error) == false)
    }
}

// MARK: - Incident Lifecycle Tests

@Suite("Outage Incident Lifecycle")
struct OutageIncidentLifecycleTests {

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600), windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(86400), windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    @Test @MainActor func noIncidentInitially() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func firstOutageCreatesIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident != nil)
        #expect(viewModel.isClaudeServiceDown == true)
        #expect(viewModel.activeClaudeIncident?.lastErrorCode == 503)
    }

    @Test @MainActor func repeatedOutageKeepsStartedAtAndUpdatesLastFailure() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // First outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        let startedAt = viewModel.activeClaudeIncident?.startedAt
        #expect(startedAt != nil)

        // Wait briefly so timestamps differ
        try? await Task.sleep(for: .milliseconds(50))

        // Second outage with different error
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(502))
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident?.startedAt == startedAt)
        #expect(viewModel.activeClaudeIncident?.lastErrorCode == 502)
    }

    @Test @MainActor func successfulFetchClearsIncident() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // Create an outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        #expect(viewModel.isClaudeServiceDown == true)

        // Successful fetch
        await mockAPI.setMockError(nil)
        await mockAPI.setMockSnapshot(makeSnapshot())
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func nonOutageErrorDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.rateLimited(retryAfter: 30))

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
        #expect(viewModel.isClaudeServiceDown == false)
    }

    @Test @MainActor func unauthorizedDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.unauthorized)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
    }

    @Test @MainActor func clientServerErrorDoesNotCreateIncident() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(404))

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident == nil)
    }
}

// MARK: - Regression Tests

@Suite("Outage Tracking Regressions")
struct OutageRegressionTests {

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600), windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(86400), windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    @Test @MainActor func errorMessageStillSetOnOutage() async {
        let mockAPI = MockAPIService()
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)

        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        await viewModel.refresh(force: true)

        // errorMessage should still be set (existing behavior preserved)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func cachedDataStillUsedOnOutage() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // First, load valid data
        let snapshot = makeSnapshot()
        await mockAPI.setMockSnapshot(snapshot)
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isUsingCachedData == false)

        // Now simulate outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serverError(500))
        await mockAPI.setMockSnapshot(nil)
        await viewModel.refresh(force: true)

        // Should use cached data AND track outage
        #expect(viewModel.isUsingCachedData == true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isClaudeServiceDown == true)
    }

    @Test @MainActor func nonOutageErrorDoesNotAffectExistingIncident() async {
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

        // Create an outage
        await mockAPI.setMockError(ClaudeAPIService.APIError.serviceUnavailable)
        await viewModel.refresh(force: true)
        let incident = viewModel.activeClaudeIncident
        #expect(incident != nil)

        // Non-outage error should not clear the incident
        await mockAPI.setMockError(ClaudeAPIService.APIError.rateLimited(retryAfter: 10))
        await viewModel.refresh(force: true)

        #expect(viewModel.activeClaudeIncident?.startedAt == incident?.startedAt)
    }
}
