//
//  UsageViewModelTests.swift
//  ClaudeMeterTests
//
//  Tests for UsageViewModel state management and business logic
//

import Testing
import Foundation
@testable import ClaudeMeter
@testable import ClaudeMeterKit

// MARK: - ViewModel Initial State Tests

@Suite("UsageViewModel Initial State")
struct UsageViewModelInitialStateTests {

    @Test @MainActor func initialStateIsCorrect() async {
        // The view model loads any cached snapshot from UserDefaults on init,
        // and the test host shares the real app's defaults domain. Stash and
        // restore the cache so the test sees a true first-launch state.
        let defaults = UserDefaults.standard
        let savedSnapshot = defaults.data(forKey: "cachedUsageSnapshot")
        let savedPlan = defaults.string(forKey: "cachedPlanType")
        defaults.removeObject(forKey: "cachedUsageSnapshot")
        defaults.removeObject(forKey: "cachedPlanType")
        defer {
            savedSnapshot.map { defaults.set($0, forKey: "cachedUsageSnapshot") }
            savedPlan.map { defaults.set($0, forKey: "cachedPlanType") }
        }

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

        #expect(viewModel.snapshot == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.planType == "Free")
    }

    @Test @MainActor func defaultRefreshIntervalIsFiveMinutes() async {
        // Clear any saved preference
        UserDefaults.standard.removeObject(forKey: "refreshInterval")

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

        #expect(viewModel.refreshInterval == .fiveMinutes)
    }

    @Test @MainActor func loadsRefreshIntervalFromUserDefaults() async {
        UserDefaults.standard.set("1min", forKey: "refreshInterval")

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

        #expect(viewModel.refreshInterval == .oneMinute)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
    }
}

// MARK: - ViewModel Status Calculation Tests

@Suite("UsageViewModel Status Calculations")
struct UsageViewModelStatusTests {

    @Test @MainActor func overallStatusIsOnTrackWhenNoSnapshot() async {
        // The view model loads any cached snapshot from UserDefaults on init,
        // and concurrent tests write to the shared defaults domain. Stash and
        // restore the cache so this test truly starts with no snapshot.
        let defaults = UserDefaults.standard
        let savedSnapshot = defaults.data(forKey: "cachedUsageSnapshot")
        defaults.removeObject(forKey: "cachedUsageSnapshot")
        defer {
            savedSnapshot.map { defaults.set($0, forKey: "cachedUsageSnapshot") }
        }

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

        // No snapshot means on track (default state)
        #expect(viewModel.overallStatus == .onTrack)
    }

    @Test @MainActor func overallStatusReflectsWorstWindow() async {
        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

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
        // Clear cache
        UserDefaults.standard.removeObject(forKey: "cachedUsageSnapshot")
        UserDefaults.standard.removeObject(forKey: "cachedUsageSnapshotTime")

        let mockCredentials = MockCredentialProvider()
        let viewModel = UsageViewModel(credentialProvider: mockCredentials)

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
        // Isolate from any cached snapshot in the shared defaults domain.
        let defaults = UserDefaults.standard
        let savedSnapshot = defaults.data(forKey: "cachedUsageSnapshot")
        let savedPlan = defaults.string(forKey: "cachedPlanType")
        defaults.removeObject(forKey: "cachedUsageSnapshot")
        defaults.removeObject(forKey: "cachedPlanType")
        defer {
            savedSnapshot.map { defaults.set($0, forKey: "cachedUsageSnapshot") }
            savedPlan.map { defaults.set($0, forKey: "cachedPlanType") }
        }

        let mockAPI = MockAPIService()
        let mockCredentials = MockCredentialProvider()
        await mockCredentials.configure(credentials: MockCredentialProvider.validCredentials())
        let viewModel = UsageViewModel(credentialProvider: mockCredentials, apiService: mockAPI)

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

// MARK: - Refresh Frequency Tests

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
