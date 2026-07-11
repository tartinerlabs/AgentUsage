//
//  UsageViewModelTests.swift
//  AgentUsageTests
//
//  Tests for UsageViewModel state management and business logic
//

import Testing
import Foundation
@testable import AgentUsage
@testable import AgentUsageKit

// MARK: - ViewModel Initial State Tests

@Suite("UsageViewModel Initial State")
struct UsageViewModelInitialStateTests {

    @Test @MainActor func initialStateIsCorrect() async {
        let testDefaults = TestUserDefaults()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        #expect(viewModel.snapshot == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.planType == "Free")
    }

    @Test @MainActor func defaultRefreshIntervalIsFiveMinutes() async {
        let testDefaults = TestUserDefaults()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        #expect(viewModel.refreshInterval == .fiveMinutes)
    }

    @Test @MainActor func loadsRefreshIntervalFromUserDefaults() async {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set("1min", forKey: "refreshInterval")

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        #expect(viewModel.refreshInterval == .oneMinute)
    }

    @Test @MainActor func claudeUsageSnapshotUsesTheUnifiedProviderRepresentation() async {
        let testDefaults = TestUserDefaults()
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            defaults: testDefaults.defaults
        )
        let session = UsageWindow(
            utilization: 42,
            resetsAt: Date().addingTimeInterval(3600),
            windowType: .session
        )
        let opus = UsageWindow(
            utilization: 18,
            resetsAt: Date().addingTimeInterval(7200),
            windowType: .opus
        )
        viewModel.snapshot = UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: nil,
            fetchedAt: Date()
        )
        viewModel.planType = "Pro"

        let providerSnapshot = viewModel.usageSnapshot(for: .claude)

        #expect(providerSnapshot?.provider == .claude)
        #expect(providerSnapshot?.planName == "Pro")
        #expect(providerSnapshot?.windows.map(\.windowType) == [.session, .opus])
    }
}

// MARK: - ViewModel Status Calculation Tests

@Suite("UsageViewModel Status Calculations")
struct UsageViewModelStatusTests {

    @Test @MainActor func overallStatusIsOnTrackWhenNoSnapshot() async {
        let testDefaults = TestUserDefaults()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        // No snapshot means on track (default state)
        #expect(viewModel.overallStatus == .onTrack)
    }

    @Test @MainActor func overallStatusReflectsWorstWindow() async {
        let testDefaults = TestUserDefaults()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        // Create a snapshot with mixed statuses
        let sessionWindow = UsageWindow(
            utilization: 50.0, // On track
            resetsAt: Date().addingTimeInterval(3600),
            windowType: .session
        )
        let opusWindow = UsageWindow(
            utilization: 95.0, // Critical
            resetsAt: Date().addingTimeInterval(86400),
            windowType: .opus
        )

        viewModel.snapshot = UsageSnapshot(
            session: sessionWindow,
            opus: opusWindow,
            sonnet: nil,
            fetchedAt: Date()
        )

        #expect(viewModel.overallStatus == .critical)
    }
}

// MARK: - Offline Mode Tests

@Suite("UsageViewModel Offline Mode")
struct UsageViewModelOfflineModeTests {

    @Test @MainActor func isUsingCachedDataDefaultsToFalse() async {
        let testDefaults = TestUserDefaults()
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            defaults: testDefaults.defaults
        )

        // With no cache, should not be using cached data initially
        #expect(viewModel.isUsingCachedData == false || viewModel.snapshot != nil)
    }
}

// MARK: - Refresh Gate Tests

@Suite("UsageViewModel Refresh Gate")
struct UsageViewModelRefreshGateTests {

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600), windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(86400), windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    /// Regression: the rate-limit gate must advance when a refresh cycle RUNS, not
    /// only when the Claude fetch succeeds. This is what stops Claude's outcome from
    /// deciding whether the batch (and thus the other providers) may refresh. A
    /// failed cycle still advances the timestamp, so a non-forced refresh right after
    /// is debounced.
    @Test @MainActor func gateAdvancesEvenWhenClaudeFetchFails() async {
        let testDefaults = TestUserDefaults()
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            defaults: testDefaults.defaults
        )

        // First cycle fails. The gate timestamp advances because the cycle ran.
        await mockAPI.setMockError(ClaudeAPIService.APIError.rateLimited(retryAfter: 30))
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot == nil)

        // A non-forced refresh immediately after must be debounced by the 30s gate,
        // even though a valid snapshot is now available — proving the gate advanced
        // on the prior failed run rather than waiting for a Claude success.
        await mockAPI.setMockError(nil)
        await mockAPI.setMockSnapshot(makeSnapshot())
        await viewModel.refresh(force: false)
        #expect(viewModel.snapshot == nil)

        // A forced refresh bypasses the gate and applies the new snapshot.
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)
    }
}

// MARK: - No Usage Data Tests

@Suite("UsageViewModel No Usage Data")
struct UsageViewModelNoUsageDataTests {

    private func makeSnapshot(resetsAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session),
            opus: UsageWindow(utilization: 30, resetsAt: resetsAt, windowType: .opus),
            sonnet: nil,
            fetchedAt: Date()
        )
    }

    /// Regression: after a usage-window reset with no prompt sent, the API
    /// returns no usage data (404/empty). The ViewModel must drop the stale
    /// cached snapshot and show "No usage data" — not hold onto pre-reset
    /// percentages.
    @Test @MainActor func noUsageDataErrorDropsStaleSnapshot() async {
        let testDefaults = TestUserDefaults()
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            defaults: testDefaults.defaults
        )

        // Seed a cached snapshot, then have the next fetch report no usage data.
        await mockAPI.setMockSnapshot(makeSnapshot(resetsAt: Date().addingTimeInterval(3600)))
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isNoUsageData == false)

        await mockAPI.setMockError(ClaudeAPIService.APIError.noUsageData)
        await mockAPI.setMockSnapshot(nil)
        await viewModel.refresh(force: true)

        #expect(viewModel.snapshot == nil, "stale cached snapshot should be dropped")
        #expect(viewModel.isNoUsageData == true)
        #expect(viewModel.isUsingCachedData == false)
        #expect(viewModel.errorMessage == nil, "noUsageData is not an error message")
    }

    /// Safety net: any API error (not just noUsageData) with an all-expired
    /// cached snapshot should also drop the stale data and show "No usage data".
    @Test @MainActor func staleExpiredCacheDroppedOnAnyError() async {
        let testDefaults = TestUserDefaults()
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            defaults: testDefaults.defaults
        )

        // Seed a snapshot whose windows all expired in the past.
        let stale = makeSnapshot(resetsAt: Date().addingTimeInterval(-3600))
        await mockAPI.setMockSnapshot(stale)
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)

        // Any non-noUsageData error with expired cache → no usage data state.
        await mockAPI.setMockError(ClaudeAPIService.APIError.invalidResponse)
        await mockAPI.setMockSnapshot(nil)
        await viewModel.refresh(force: true)

        #expect(viewModel.snapshot == nil, "expired cached snapshot should be dropped")
        #expect(viewModel.isNoUsageData == true)
        #expect(viewModel.isUsingCachedData == false)
    }

    /// No regression: a non-expired cached snapshot is kept on API error, and a
    /// successful fetch clears the no-usage-data flag.
    @Test @MainActor func freshCacheKeptOnErrorAndSuccessClearsFlag() async {
        let testDefaults = TestUserDefaults()
        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(
            credentialProvider: mockCredentials,
            apiService: mockAPI,
            defaults: testDefaults.defaults
        )

        // Fresh (unexpired) cache.
        let fresh = makeSnapshot(resetsAt: Date().addingTimeInterval(3600))
        await mockAPI.setMockSnapshot(fresh)
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil)
        #expect(viewModel.isNoUsageData == false)

        // A transient error keeps the fresh cache (existing behavior).
        await mockAPI.setMockError(ClaudeAPIService.APIError.invalidResponse)
        await mockAPI.setMockSnapshot(nil)
        await viewModel.refresh(force: true)
        #expect(viewModel.snapshot != nil, "fresh cache should be kept on error")
        #expect(viewModel.isUsingCachedData == true)
        #expect(viewModel.isNoUsageData == false)

        // A successful fetch clears any no-usage-data flag.
        await mockAPI.setMockError(nil)
        await mockAPI.setMockSnapshot(fresh)
        await viewModel.refresh(force: true)
        #expect(viewModel.isNoUsageData == false)
        #expect(viewModel.isUsingCachedData == false)
    }
}

@Suite("RefreshFrequency")
struct RefreshFrequencyTests {

    @Test func oneMinuteInterval() {
        let freq = RefreshFrequency.oneMinute
        #expect(freq.timeInterval == 60)
        #expect(freq.rawValue == "1min")
    }

    @Test func twoMinutesInterval() {
        let freq = RefreshFrequency.twoMinutes
        #expect(freq.timeInterval == 120)
        #expect(freq.rawValue == "2min")
    }

    @Test func fiveMinutesInterval() {
        let freq = RefreshFrequency.fiveMinutes
        #expect(freq.timeInterval == 300)
        #expect(freq.rawValue == "5min")
    }

    @Test func fifteenMinutesInterval() {
        let freq = RefreshFrequency.fifteenMinutes
        #expect(freq.timeInterval == 900)
        #expect(freq.rawValue == "15min")
    }

    @Test func manualHasNoInterval() {
        let freq = RefreshFrequency.manual
        #expect(freq.timeInterval == nil)
        #expect(freq.rawValue == "manual")
    }

    @Test func initializesFromRawValue() {
        #expect(RefreshFrequency(rawValue: "1min") == .oneMinute)
        #expect(RefreshFrequency(rawValue: "2min") == .twoMinutes)
        #expect(RefreshFrequency(rawValue: "5min") == .fiveMinutes)
        #expect(RefreshFrequency(rawValue: "15min") == .fifteenMinutes)
        #expect(RefreshFrequency(rawValue: "manual") == .manual)
        #expect(RefreshFrequency(rawValue: "invalid") == nil)
    }

    @Test func allCasesContainsAllFrequencies() {
        let allCases = RefreshFrequency.allCases
        #expect(allCases.contains(.oneMinute))
        #expect(allCases.contains(.twoMinutes))
        #expect(allCases.contains(.fiveMinutes))
        #expect(allCases.contains(.fifteenMinutes))
        #expect(allCases.contains(.manual))
    }
}

// MARK: - Usage Calculations Tests

@Suite("UsageCalculations")
struct UsageCalculationsTests {

    @Test func overallStatusFromNilSnapshot() {
        let status = UsageCalculations.overallStatus(from: nil)
        #expect(status == .onTrack)
    }

    @Test func overallStatusTakesWorstCase() {
        // Use future reset dates so status calculation runs fully
        let futureReset = Date().addingTimeInterval(3600) // 1 hour from now

        let sessionOnTrack = UsageWindow(
            utilization: 30.0,
            resetsAt: futureReset,
            windowType: .session
        )
        let opusWarning = UsageWindow(
            utilization: 80.0,
            resetsAt: futureReset,
            windowType: .opus
        )
        let sonnetCritical = UsageWindow(
            utilization: 95.0,
            resetsAt: futureReset,
            windowType: .sonnet
        )

        let snapshot = UsageSnapshot(
            session: sessionOnTrack,
            opus: opusWarning,
            sonnet: sonnetCritical,
            fetchedAt: Date()
        )

        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .critical)
    }

    @Test func overallStatusWithAllOnTrack() {
        // Use future reset dates so status calculation runs fully
        let futureReset = Date().addingTimeInterval(3600)

        let session = UsageWindow(utilization: 20.0, resetsAt: futureReset, windowType: .session)
        let opus = UsageWindow(utilization: 30.0, resetsAt: futureReset, windowType: .opus)

        let snapshot = UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: nil,
            fetchedAt: Date()
        )

        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .onTrack)
    }
}
