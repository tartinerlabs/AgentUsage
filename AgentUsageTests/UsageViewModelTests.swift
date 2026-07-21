//
//  UsageViewModelTests.swift
//  AgentUsageTests
//
//  Tests for UsageViewModel state management and business logic
//

import Testing
import Foundation
#if os(iOS)
import UIKit
#endif
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

    #if os(macOS)
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
    #endif
}

@Suite("UsageViewModel Notifications")
struct UsageViewModelNotificationTests {
    @Test @MainActor func enablingNotificationsRequestsAndPersistsPermission() async {
        let testDefaults = TestUserDefaults()
        let notifications = MockNotificationService()
        await notifications.configurePermission(state: .notDetermined, grantsPermission: true)
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            notificationService: notifications,
            defaults: testDefaults.defaults
        )

        await viewModel.setNotificationsEnabled(true)

        #expect(viewModel.notificationsEnabled)
        #expect(viewModel.notificationPermissionState == .authorized)
        #expect(testDefaults.defaults.bool(forKey: "notificationsEnabled"))
        #expect(await notifications.permissionRequestCount == 1)
    }

    @Test @MainActor func deniedPermissionDisablesStoredPreference() async {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: "notificationsEnabled")
        let notifications = MockNotificationService()
        await notifications.configurePermission(state: .denied, grantsPermission: false)
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            notificationService: notifications,
            defaults: testDefaults.defaults
        )

        await viewModel.refreshNotificationPermissionState()

        #expect(!viewModel.notificationsEnabled)
        #expect(viewModel.notificationPermissionState == .denied)
        #expect(!testDefaults.defaults.bool(forKey: "notificationsEnabled"))
    }

    @Test @MainActor func testNotificationUsesInjectedServiceWithoutUsageDataOrPreference() async {
        let notifications = MockNotificationService()
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            notificationService: notifications,
            defaults: TestUserDefaults().defaults
        )

        await viewModel.sendTestNotification()

        #expect(!viewModel.notificationsEnabled)
        #expect(viewModel.snapshot == nil)
        #expect(viewModel.notificationTestResult == .sent)
        #expect(await notifications.testNotificationCount == 1)
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

// MARK: - Verified Continuity Sync Tests

#if os(macOS)
@Suite("UsageViewModel verified continuity sync")
struct UsageViewModelVerifiedContinuitySyncTests {
    @Test @MainActor func localSnapshotAloneDoesNotClaimAConnection() {
        let viewModel = makeViewModel(syncService: MockUsageSyncService())
        viewModel.snapshot = Self.snapshot()

        #expect(viewModel.appConnectionStatus == .waitingForDevices(message: nil))
        #expect(viewModel.continuityNetworkStatus.mac == .waiting(lastSeenAt: nil))
        #expect(viewModel.continuityNetworkStatus.iPhone == .unavailable)
        #expect(viewModel.continuityNetworkStatus.iPad == .unavailable)
    }

    @Test @MainActor func matchingIPhoneReceiptVerifiesOnlyIPhone() async {
        let acknowledgedAt = Date()
        let syncService = MockUsageSyncService()
        await syncService.configurePublication(generation: "current")
        await syncService.configureReceipts([
            .iPhone: ContinuityReceipt(
                device: .iPhone,
                syncGeneration: "current",
                acknowledgedAt: acknowledgedAt
            ),
        ])
        let viewModel = makeViewModel(syncService: syncService)
        viewModel.snapshot = Self.snapshot()

        await viewModel.refreshContinuitySync()

        #expect(viewModel.appConnectionStatus == .linked(lastUpdatedText: nil))
        #expect(viewModel.continuityNetworkStatus.iPhone == .connected(lastSeenAt: acknowledgedAt))
        #expect(viewModel.continuityNetworkStatus.iPad == .unavailable)
    }

    @Test @MainActor func staleReceiptDoesNotVerifyLatestGeneration() async {
        let lastSeenAt = Date().addingTimeInterval(-3600)
        let syncService = MockUsageSyncService()
        await syncService.configurePublication(generation: "current")
        await syncService.configureReceipts([
            .iPhone: ContinuityReceipt(
                device: .iPhone,
                syncGeneration: "previous",
                acknowledgedAt: lastSeenAt
            ),
        ])
        let viewModel = makeViewModel(syncService: syncService)
        viewModel.snapshot = Self.snapshot()

        await viewModel.refreshContinuitySync()

        #expect(viewModel.appConnectionStatus == .waitingForDevices(message: nil))
        #expect(viewModel.continuityNetworkStatus.iPhone == .waiting(lastSeenAt: lastSeenAt))
    }

    @Test @MainActor func publishFailureIsVisibleAndDoesNotTurnGreen() async {
        let syncService = MockUsageSyncService()
        await syncService.configurePublishError(
            .recordOperationFailed(recordName: "latest", message: "schema unavailable")
        )
        let viewModel = makeViewModel(syncService: syncService)
        viewModel.snapshot = Self.snapshot()

        await viewModel.refreshContinuitySync()

        #expect(viewModel.publishedSyncGeneration == nil)
        #expect(viewModel.continuitySyncErrorMessage?.contains("schema unavailable") == true)
        guard case .needsSetup = viewModel.appConnectionStatus else {
            Issue.record("Expected a visible continuity setup error")
            return
        }
        #expect(viewModel.continuityNetworkStatus.mac == .unavailable)
    }

    @Test @MainActor func receiptCheckFailureKeepsUploadTruthfulButUnverified() async {
        let syncService = MockUsageSyncService()
        await syncService.configurePublication(generation: "current")
        await syncService.configureReceiptError(
            .recordOperationFailed(recordName: "ContinuityReceipt", message: "not authenticated")
        )
        let viewModel = makeViewModel(syncService: syncService)
        viewModel.snapshot = Self.snapshot()

        await viewModel.refreshContinuitySync()

        #expect(viewModel.publishedSyncGeneration == "current")
        #expect(viewModel.continuitySyncErrorMessage?.contains("could not verify") == true)
        guard case .waitingForDevices = viewModel.appConnectionStatus else {
            Issue.record("Expected an uploaded but unverified state")
            return
        }
        #expect(viewModel.continuityNetworkStatus.mac == .connected(lastSeenAt: viewModel.snapshot?.fetchedAt))
    }

    @Test @MainActor func successfulRetryClearsPreviousPublishError() async {
        let syncService = MockUsageSyncService()
        await syncService.configurePublishError(
            .recordOperationFailed(recordName: "latest", message: "temporary")
        )
        let viewModel = makeViewModel(syncService: syncService)
        viewModel.snapshot = Self.snapshot()
        await viewModel.refreshContinuitySync()
        #expect(viewModel.continuitySyncErrorMessage != nil)

        await syncService.configurePublishError(nil)
        await syncService.configurePublication(generation: "recovered")
        await viewModel.refreshContinuitySync()

        #expect(viewModel.publishedSyncGeneration == "recovered")
        #expect(viewModel.continuitySyncErrorMessage == nil)
    }

    @Test @MainActor func macRevokeRemovesTheWholeContinuitySetup() async {
        let syncService = MockUsageSyncService()
        let viewModel = makeViewModel(syncService: syncService)

        await viewModel.revokeAppConnection()

        #expect(await syncService.didRevokeAll())
        #expect(await syncService.revokedDeviceValues().isEmpty)
    }

    @MainActor
    private func makeViewModel(syncService: MockUsageSyncService) -> UsageViewModel {
        UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            defaults: TestUserDefaults().defaults
        )
    }

    private static func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: 20,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 30,
                resetsAt: Date().addingTimeInterval(7200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )
    }
}
#endif

#if os(iOS)
@Suite("UsageViewModel mobile continuity acknowledgement")
struct UsageViewModelMobileContinuityTests {
    @Test @MainActor func cachedPreThresholdSnapshotAlertsAfterRelaunch() async {
        let reset = Date().addingTimeInterval(3_600)
        let cached = Self.snapshot(session: 20, reset: reset, fetchedAt: Date())
        let crossed = Self.snapshot(
            session: 30,
            reset: reset,
            fetchedAt: cached.fetchedAt.addingTimeInterval(60)
        )
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: "notificationsEnabled")
        UsageSnapshotStore(defaults: testDefaults.defaults).save(
            snapshot: cached,
            planType: "Pro",
            fetchedAt: cached.fetchedAt
        )
        let syncService = MockUsageSyncService()
        await syncService.configureFetchedSnapshot(Self.synced(crossed))
        let notifications = MockNotificationService()
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            notificationService: notifications,
            defaults: testDefaults.defaults
        )

        await viewModel.refreshContinuitySync()

        #expect(await notifications.thresholdCheckCount == 1)
        #expect(await notifications.lastOldSnapshot?.session.percentUsed == 20)
        #expect(await notifications.lastNewSnapshot?.session.percentUsed == 30)
    }

    @Test @MainActor func notificationsEvaluateOnlyNewFreshSyncedSnapshots() async {
        let reset = Date().addingTimeInterval(3_600)
        let initial = Self.snapshot(session: 20, reset: reset, fetchedAt: Date())
        let crossed = Self.snapshot(
            session: 30,
            reset: reset,
            fetchedAt: initial.fetchedAt.addingTimeInterval(60)
        )
        let syncService = MockUsageSyncService()
        let notifications = MockNotificationService()
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: "notificationsEnabled")
        await syncService.configureFetchedSnapshot(Self.synced(initial))
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            notificationService: notifications,
            defaults: testDefaults.defaults
        )

        await viewModel.refreshContinuitySync()
        await syncService.configureFetchedSnapshot(Self.synced(crossed))
        await viewModel.refreshContinuitySync()
        await viewModel.refreshContinuitySync()
        await syncService.configureFetchedSnapshot(nil)
        await viewModel.refreshContinuitySync()
        let stale = Self.snapshot(
            session: 40,
            reset: reset,
            fetchedAt: Date().addingTimeInterval(-(Constants.syncFallbackThreshold + 60))
        )
        await syncService.configureFetchedSnapshot(Self.synced(stale))
        await viewModel.refreshContinuitySync()

        #expect(await notifications.thresholdCheckCount == 2)
        #expect(await notifications.lastOldSnapshot?.session.percentUsed == 20)
        #expect(await notifications.lastNewSnapshot?.session.percentUsed == 30)
    }

    @Test @MainActor func disabledUsageAlertsSkipSyncedSnapshotEvaluation() async {
        let syncService = MockUsageSyncService()
        let notifications = MockNotificationService()
        let snapshot = Self.snapshot(
            session: 30,
            reset: Date().addingTimeInterval(3_600),
            fetchedAt: Date()
        )
        await syncService.configureFetchedSnapshot(Self.synced(snapshot))
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            notificationService: notifications,
            defaults: TestUserDefaults().defaults
        )

        await viewModel.refreshContinuitySync()

        #expect(!viewModel.notificationsEnabled)
        #expect(await notifications.thresholdCheckCount == 0)
    }

    @Test @MainActor func syncedProviderSnapshotsAreAvailableOnMobile() async {
        let snapshot = Self.snapshot()
        let codexWindow = UsageWindow(
            utilization: 54,
            resetsAt: Date().addingTimeInterval(3_600),
            windowType: .codexFiveHour
        )
        let codexSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [codexWindow],
            planName: "Plus",
            fetchedAt: snapshot.fetchedAt
        )
        let syncService = MockUsageSyncService()
        await syncService.configureFetchedSnapshot(
            SyncedUsageSnapshot(
                snapshot: snapshot,
                planType: "Pro",
                providerSnapshots: [codexSnapshot],
                fetchedAt: snapshot.fetchedAt,
                syncGeneration: "mobile-generation"
            )
        )
        let viewModel = Self.makeViewModel(syncService: syncService)

        await viewModel.refreshContinuitySync()

        #expect(viewModel.usageSnapshot(for: .codex)?.planName == "Plus")
        #expect(viewModel.usageSnapshot(for: .codex)?.windows.map(\.windowType) == [.codexFiveHour])
        #expect(viewModel.hasProviderData(.codex))
    }

    @Test @MainActor func receiptFailureDoesNotDiscardFetchedSnapshot() async {
        let snapshot = UsageSnapshot(
            session: UsageWindow(
                utilization: 20,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 30,
                resetsAt: Date().addingTimeInterval(7200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )
        let syncService = MockUsageSyncService()
        await syncService.configureFetchedSnapshot(
            SyncedUsageSnapshot(
                snapshot: snapshot,
                planType: "Pro",
                fetchedAt: snapshot.fetchedAt,
                syncGeneration: "mobile-generation"
            )
        )
        await syncService.configureAcknowledgementError(
            .recordOperationFailed(recordName: "continuity-iphone", message: "offline")
        )
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            defaults: TestUserDefaults().defaults
        )

        await viewModel.refreshContinuitySync()

        #expect(viewModel.snapshot?.fetchedAt == snapshot.fetchedAt)
        guard case .syncedFromMac = viewModel.appConnectionStatus else {
            Issue.record("Expected the fetched snapshot to remain applied")
            return
        }
        #expect(await syncService.acknowledgementCount() == 1)
    }

    @Test @MainActor func receiptWriteRecoversOnTheNextRefresh() async {
        let snapshot = Self.snapshot()
        let syncService = MockUsageSyncService()
        await syncService.configureFetchedSnapshot(
            SyncedUsageSnapshot(
                snapshot: snapshot,
                planType: "Pro",
                fetchedAt: snapshot.fetchedAt,
                syncGeneration: "mobile-generation"
            )
        )
        await syncService.configureAcknowledgementError(
            .recordOperationFailed(recordName: "continuity-mobile", message: "offline")
        )
        let viewModel = Self.makeViewModel(syncService: syncService)

        await viewModel.refreshContinuitySync()
        #expect(await syncService.successfullyAcknowledgedDevices().isEmpty)

        await syncService.configureAcknowledgementError(nil)
        await viewModel.refreshContinuitySync()

        #expect(await syncService.successfullyAcknowledgedDevices().count == 1)
        #expect(viewModel.snapshot?.fetchedAt == snapshot.fetchedAt)
    }

    @Test @MainActor func mobileRevokeRemovesOnlyTheCurrentPlatformReceipt() async {
        let syncService = MockUsageSyncService()
        let viewModel = Self.makeViewModel(syncService: syncService)
        let expectedDevice: UsageSyncDevice = UIDevice.current.userInterfaceIdiom == .pad
            ? .iPad
            : .iPhone

        await viewModel.revokeAppConnection()

        #expect(await syncService.didRevokeAll() == false)
        #expect(await syncService.revokedDeviceValues() == [expectedDevice])
    }

    @MainActor
    private static func makeViewModel(syncService: MockUsageSyncService) -> UsageViewModel {
        UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageSyncService: syncService,
            defaults: TestUserDefaults().defaults
        )
    }

    private static func snapshot() -> UsageSnapshot {
        snapshot(
            session: 20,
            reset: Date().addingTimeInterval(3_600),
            fetchedAt: Date()
        )
    }

    private static func snapshot(
        session: Double,
        reset: Date,
        fetchedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: session,
                resetsAt: reset,
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 30,
                resetsAt: Date().addingTimeInterval(7200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: fetchedAt
        )
    }

    private static func synced(_ snapshot: UsageSnapshot) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            snapshot: snapshot,
            planType: "Pro",
            fetchedAt: snapshot.fetchedAt
        )
    }
}
#endif

actor MockUsageSyncService: UsageSyncServicing {
    private var publication = PublishedUsageSnapshot(
        syncGeneration: "generation",
        fetchedAt: Date()
    )
    private var publishError: UsageSyncError?
    private var fetchedSnapshot: SyncedUsageSnapshot?
    private var acknowledgementError: UsageSyncError?
    private var receiptValues: [UsageSyncDevice: ContinuityReceipt] = [:]
    private var receiptError: UsageSyncError?
    private var acknowledgementCalls = 0
    private var acknowledgedDevices: [UsageSyncDevice] = []
    private var revokedDevices: [UsageSyncDevice] = []
    private var revokedAll = false

    func configurePublication(generation: String) {
        publication = PublishedUsageSnapshot(syncGeneration: generation, fetchedAt: Date())
    }

    func configurePublishError(_ error: UsageSyncError?) {
        publishError = error
    }

    func configureFetchedSnapshot(_ snapshot: SyncedUsageSnapshot?) {
        fetchedSnapshot = snapshot
    }

    func configureAcknowledgementError(_ error: UsageSyncError?) {
        acknowledgementError = error
    }

    func configureReceipts(_ receipts: [UsageSyncDevice: ContinuityReceipt]) {
        receiptValues = receipts
    }

    func configureReceiptError(_ error: UsageSyncError?) {
        receiptError = error
    }

    func acknowledgementCount() -> Int {
        acknowledgementCalls
    }

    func successfullyAcknowledgedDevices() -> [UsageSyncDevice] {
        acknowledgedDevices
    }

    func revokedDeviceValues() -> [UsageSyncDevice] {
        revokedDevices
    }

    func didRevokeAll() -> Bool {
        revokedAll
    }

    func publish(
        snapshot: UsageSnapshot,
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot]
    ) async throws -> PublishedUsageSnapshot {
        if let publishError { throw publishError }
        return publication
    }

    func fetchLatest() async -> SyncedUsageSnapshot? {
        fetchedSnapshot
    }

    func acknowledge(
        snapshot: SyncedUsageSnapshot,
        from device: UsageSyncDevice
    ) async throws -> ContinuityReceipt {
        acknowledgementCalls += 1
        if let acknowledgementError { throw acknowledgementError }
        acknowledgedDevices.append(device)
        return ContinuityReceipt(
            device: device,
            syncGeneration: snapshot.syncGeneration ?? "",
            acknowledgedAt: Date()
        )
    }

    func fetchReceipts() async throws -> [UsageSyncDevice: ContinuityReceipt] {
        if let receiptError { throw receiptError }
        return receiptValues
    }

    func revokeAll() async -> Bool {
        revokedAll = true
        return true
    }

    func revoke(device: UsageSyncDevice) async -> Bool {
        revokedDevices.append(device)
        return true
    }
}
