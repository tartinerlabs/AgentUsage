//
//  UsageViewModel.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit
import SwiftUI
import OSLog
#if os(iOS)
import UIKit
#endif

/// Safe default for tests and previews that construct a view model outside the
/// app's dependency container. Production explicitly injects CloudKit below.
actor InactiveUsageSyncService: UsageSyncServicing {
    static let shared = InactiveUsageSyncService()

    private let unavailableError = UsageSyncError.recordOperationFailed(
        recordName: "ContinuitySync",
        message: "Continuity Sync is not configured for this view model."
    )

    func publish(
        snapshot _: UsageSnapshot?,
        planType _: String,
        providerSnapshots _: [ProviderUsageSnapshot]
    ) async throws -> PublishedUsageSnapshot {
        throw unavailableError
    }

    func fetchLatest() async -> SyncedUsageSnapshot? {
        nil
    }

    func acknowledge(
        snapshot _: SyncedUsageSnapshot,
        from _: UsageSyncDevice
    ) async throws -> ContinuityReceipt {
        throw unavailableError
    }

    func fetchReceipts() async throws -> [UsageSyncDevice: ContinuityReceipt] {
        [:]
    }

    func revokeAll() async -> Bool {
        true
    }

    func revoke(device _: UsageSyncDevice) async -> Bool {
        true
    }
}

@MainActor @Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot?
    var tokenSnapshot: TokenUsageSnapshot?
    var selectedPeriodSummary: TokenUsageSummary?
    #if os(macOS)
    var periodSummaries: [UsagePeriod: TokenUsageSummary] = [:]
    #endif
    /// Rate-limit windows for optional providers. Claude remains backed by its
    /// cached `UsageSnapshot` because its API model is richer and shared with
    /// iOS and WidgetKit.
    private(set) var providerUsage: [Provider: ProviderUsageSnapshot] = [:]
    #if os(macOS)
    /// Full per-provider detail (today/yesterday/30-day, per-model, daily trend)
    /// for all providers (Claude, Codex, OpenCode).
    var providerDetails: [Provider: ProviderDetail] = [:]
    #endif
    var planType: String = "Free"
    var isLoading = false
    var errorMessage: String?
    var appConnectionRevoked = false {
        didSet {
            defaults.set(appConnectionRevoked, forKey: Constants.continuitySyncRevokedKey)
        }
    }
    var isRevokingAppConnection = false
    var isRefreshingContinuitySync = false
    var continuitySyncErrorMessage: String?
    #if os(macOS)
    private(set) var publishedSyncGeneration: String?
    private(set) var continuityReceipts: [UsageSyncDevice: ContinuityReceipt] = [:]
    private(set) var isCheckingContinuityReceipts = false
    #endif
    #if os(macOS)
    var tokenUsageError: TokenUsageError?
    var isLoadingTokenUsage = false
    var blogUsageSyncEnabled: Bool {
        didSet {
            guard blogUsageSyncEnabled != oldValue else { return }
            Task {
                await blogUsageSyncService?.setEnabled(blogUsageSyncEnabled)
                await loadBlogUsageSyncSettings()
            }
        }
    }
    var blogUsageSyncEndpointURLString: String {
        didSet {
            guard blogUsageSyncEndpointURLString != oldValue else { return }
            Task {
                await blogUsageSyncService?.setEndpointURLString(blogUsageSyncEndpointURLString)
                await loadBlogUsageSyncSettings()
            }
        }
    }
    var blogUsageSyncToken: String = ""
    var blogUsageSyncStatus: BlogUsageSyncStatus = .never
    var isBlogUsageSyncing = false
    // Blog OAuth sign-in state
    var isBlogSignedIn = false
    var blogOAuthAccountEmail: String?
    var isBlogSigningIn = false
    var blogOAuthError: String?
    #endif
    var selectedTokenPeriod: UsagePeriod = .last30Days {
        didSet {
            #if os(macOS)
            // Instant update from cache (if available); defer fetch to view with .task(id:)
            selectedPeriodSummary = periodSummaries[selectedTokenPeriod]
            #endif
        }
    }

    // MARK: - Offline Support

    /// Whether we're using cached data (offline or stale)
    var isUsingCachedData: Bool = false

    /// True when the Claude usage endpoint reports no usage data yet — the
    /// usage windows have reset but no prompt has been sent since. The UI shows
    /// a "No usage data" state instead of stale cached meters or a spinner.
    var isNoUsageData: Bool = false

    #if os(iOS)
    /// True after iOS has applied a snapshot published by the Mac app during this session.
    private var receivedMacSyncedSnapshot = false
    #endif

    // MARK: - Outage Tracking

    /// Active outage incidents keyed by provider. An entry exists while a provider's
    /// most recent usage fetch failed with an outage-class error (HTTP 5xx / service
    /// unavailable); it is cleared on the next successful fetch.
    var activeIncidents: [Provider: OutageIncident] = [:]

    /// The active Claude incident, if any.
    var activeClaudeIncident: OutageIncident? { activeIncidents[.claude] }

    /// Whether Claude's service is currently considered down.
    var isClaudeServiceDown: Bool { activeIncidents[.claude] != nil }

    /// The active incident for a provider, if any.
    func activeIncident(for provider: Provider) -> OutageIncident? { activeIncidents[provider] }

    /// Whether the given provider's service is currently considered down.
    func isServiceDown(_ provider: Provider) -> Bool { activeIncidents[provider] != nil }

    /// Whether an error indicates a provider outage (HTTP 5xx / service unavailable),
    /// as opposed to client errors, auth failures, rate limiting, or connectivity.
    nonisolated static func isOutageError(_ error: Error) -> Bool {
        outageErrorCode(error) != nil
    }

    /// Maps an outage-class error to its HTTP status code, or nil if it is not an outage.
    nonisolated static func outageErrorCode(_ error: Error) -> Int? {
        if let apiError = error as? ClaudeAPIService.APIError {
            switch apiError {
            case .serviceUnavailable: return 503
            case .serverError(let code) where (500...599).contains(code): return code
            default: return nil
            }
        }
        #if os(macOS)
        if let codexError = error as? CodexUsageService.CodexError {
            switch codexError {
            case .serviceUnavailable: return 503
            case .serverError(let code) where (500...599).contains(code): return code
            default: return nil
            }
        }
        #endif
        return nil
    }

    /// Record (or update) an outage incident for a provider, preserving `startedAt`.
    private func recordOutage(for provider: Provider, error: Error) {
        let code = Self.outageErrorCode(error)
        if var incident = activeIncidents[provider] {
            incident.lastErrorCode = code
            activeIncidents[provider] = incident
        } else {
            activeIncidents[provider] = OutageIncident(startedAt: Date(), lastErrorCode: code)
        }
    }

    /// Clear any active incident for a provider (called on a successful fetch).
    private func clearIncident(for provider: Provider) {
        activeIncidents[provider] = nil
    }

    /// Time since last successful fetch (for "Last updated X ago" display)
    var timeSinceLastUpdate: String? {
        guard let lastUpdate = snapshotStore.lastSuccessfulFetchTime else { return nil }
        let interval = Date().timeIntervalSince(lastUpdate)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    /// Whether the device is currently offline
    var isOffline: Bool {
        !NetworkMonitor.shared.isConnected
    }

    var refreshInterval: RefreshFrequency {
        get { refreshScheduler.refreshInterval }
        set { refreshScheduler.refreshInterval = newValue }
    }

    var showExtraUsageIndicators: Bool {
        didSet {
            defaults.set(showExtraUsageIndicators, forKey: "showExtraUsageIndicators")
        }
    }

    private(set) var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    private(set) var notificationPermissionState: NotificationPermissionState = .notDetermined
    private(set) var notificationTestResult: NotificationTestResult?

    #if os(macOS)
    var menuBarProviders: [Provider] {
        MenuBarSettingsManager.supportedProviders
    }

    func menuBarSupportedWindows(for provider: Provider) -> [UsageWindowType] {
        MenuBarSettingsManager.supportedWindows(for: provider)
    }

    func menuBarPinnedWindows(for provider: Provider) -> [UsageWindowType] {
        menuBarSettingsManager.pinnedWindows(for: provider)
    }

    func isMenuBarWindowPinned(_ window: UsageWindowType, for provider: Provider) -> Bool {
        menuBarSettingsManager.isPinned(window, for: provider)
    }

    func canPinMenuBarWindow(_ window: UsageWindowType, for provider: Provider) -> Bool {
        menuBarSettingsManager.canPin(window, for: provider)
    }

    func setMenuBarWindowPinned(
        _ window: UsageWindowType,
        for provider: Provider,
        isPinned: Bool
    ) {
        menuBarSettingsManager.setPinned(window, for: provider, isPinned: isPinned)
    }

    #if DEBUG
    var debugSimulate100Percent: Bool = false
    #endif
    #endif

    private let credentialProvider: any CredentialProvider
    private let apiService: any APIServiceProtocol
    private let usageSyncService: any UsageSyncServicing
    private let usageHistoryService: UsageHistoryService
    private let defaults: UserDefaults
    private let snapshotStore: UsageSnapshotStore
    private let refreshScheduler: RefreshScheduler
    private let notificationService: any NotificationServiceProtocol
    private static let disabledProviders: Set<Provider> = [.openCode]

    #if os(macOS)
    private let tokenUsageCoordinator: any TokenUsageCoordinating
    private let menuBarSettingsManager: MenuBarSettingsManager
    private let blogUsageSyncService: BlogUsageSyncService?
    private let blogOAuthService: BlogOAuthService?
    private let providerUsageServices: [Provider: any ProviderUsageServiceProtocol]
    #endif
    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 30
    private var hasInitialized = false

    /// While set and in the future, auto-refresh is suppressed because the endpoint
    /// returned HTTP 429. Cleared on the next successful fetch.
    private var rateLimitedUntil: Date?

    /// Overall status computed from the worst status across all usage windows
    var overallStatus: UsageStatus {
        UsageCalculations.overallStatus(from: snapshot)
    }

    /// A clear, user-facing summary of the app's connection to Claude's usage API,
    /// combining credential validity, last-fetch success, network reachability, and
    /// service outages. Rendered identically on macOS and iOS/iPadOS.
    var claudeConnectionStatus: ClaudeConnectionStatus {
        if isOffline {
            return .offline
        }
        if isClaudeServiceDown {
            return .serviceUnavailable
        }
        if isNoUsageData {
            return .noUsageData
        }
        if snapshot != nil {
            return isUsingCachedData ? .cached : .connected
        }
        if isLoading {
            return .checking
        }
        return .disconnected(message: errorMessage)
    }

    /// Provider-neutral status for how this install participates in the shared
    /// AgentUsage setup across Mac, iPhone, and iPad.
    var appConnectionStatus: AppConnectionStatus {
        if appConnectionRevoked {
            return .revoked
        }

        #if os(iOS)
        if receivedMacSyncedSnapshot {
            return .syncedFromMac(lastUpdatedText: timeSinceLastUpdate)
        }
        #endif

        #if os(macOS)
        if isRefreshingContinuitySync {
            return .checking
        }
        if publishedSyncGeneration != nil {
            if hasCurrentDeviceAcknowledgement {
                return .linked(lastUpdatedText: timeSinceLastUpdate)
            }
            return .waitingForDevices(message: continuitySyncErrorMessage)
        }
        if let continuitySyncErrorMessage {
            return .needsSetup(message: continuitySyncErrorMessage)
        }
        if snapshot != nil || isNoUsageData {
            return .waitingForDevices(message: nil)
        }
        #else
        if snapshot != nil || isNoUsageData {
            return .linked(lastUpdatedText: timeSinceLastUpdate)
        }
        #endif
        if isLoading {
            return .checking
        }
        #if os(iOS)
        if isOffline {
            return .waitingForMac
        }
        #endif
        return .needsSetup(message: errorMessage)
    }

    var continuityNetworkStatus: ContinuityNetworkStatus {
        if appConnectionRevoked {
            return ContinuityNetworkStatus(mac: .revoked, iPhone: .revoked, iPad: .revoked)
        }

        #if os(macOS)
        let macState: ContinuityNodeState
        if isRefreshingContinuitySync {
            macState = .checking
        } else if publishedSyncGeneration != nil {
            macState = .connected(lastSeenAt: snapshot?.fetchedAt)
        } else if continuitySyncErrorMessage != nil {
            macState = .unavailable
        } else {
            macState = .waiting(lastSeenAt: nil)
        }

        return ContinuityNetworkStatus(
            mac: macState,
            iPhone: continuityNodeState(for: .iPhone),
            iPad: continuityNodeState(for: .iPad)
        )
        #else
        let macState: ContinuityNodeState = receivedMacSyncedSnapshot
            ? .connected(lastSeenAt: snapshot?.fetchedAt)
            : .waiting(lastSeenAt: nil)
        let localState: ContinuityNodeState = receivedMacSyncedSnapshot
            ? .connected(lastSeenAt: snapshot?.fetchedAt)
            : .waiting(lastSeenAt: nil)
        return ContinuityNetworkStatus(
            mac: macState,
            iPhone: Self.currentSyncDevice == .iPhone ? localState : .unavailable,
            iPad: Self.currentSyncDevice == .iPad ? localState : .unavailable
        )
        #endif
    }

    #if os(macOS)
    private var hasCurrentDeviceAcknowledgement: Bool {
        guard let publishedSyncGeneration else { return false }
        return continuityReceipts.values.contains {
            $0.syncGeneration == publishedSyncGeneration
        }
    }

    private func continuityNodeState(for device: UsageSyncDevice) -> ContinuityNodeState {
        guard let receipt = continuityReceipts[device] else {
            return isCheckingContinuityReceipts ? .checking : .unavailable
        }
        guard receipt.syncGeneration == publishedSyncGeneration else {
            return .waiting(lastSeenAt: receipt.acknowledgedAt)
        }
        return .connected(lastSeenAt: receipt.acknowledgedAt)
    }
    #else
    private static var currentSyncDevice: UsageSyncDevice {
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }
    #endif

    #if os(macOS)
    init(
        credentialProvider: any CredentialProvider,
        apiService: (any APIServiceProtocol)? = nil,
        tokenUsageCoordinator: (any TokenUsageCoordinating)? = nil,
        blogUsageSyncService: BlogUsageSyncService? = nil,
        blogOAuthService: BlogOAuthService? = nil,
        providerUsageServices: [Provider: any ProviderUsageServiceProtocol] = [:],
        usageHistoryService: UsageHistoryService? = nil,
        usageSyncService: any UsageSyncServicing = InactiveUsageSyncService.shared,
        notificationService: any NotificationServiceProtocol = NotificationService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.credentialProvider = credentialProvider
        self.apiService = apiService ?? ClaudeAPIService()
        self.usageSyncService = usageSyncService
        self.usageHistoryService = usageHistoryService ?? UsageHistoryService(defaults: defaults)
        self.defaults = defaults
        self.snapshotStore = UsageSnapshotStore(defaults: defaults)
        self.refreshScheduler = RefreshScheduler(defaults: defaults)
        self.notificationService = notificationService
        self.tokenUsageCoordinator = tokenUsageCoordinator
            ?? TokenUsageCoordinator(tokenService: nil, defaults: defaults)
        self.menuBarSettingsManager = MenuBarSettingsManager(defaults: defaults)
        self.blogUsageSyncService = blogUsageSyncService
        self.blogOAuthService = blogOAuthService
        self.providerUsageServices = providerUsageServices
        self.showExtraUsageIndicators = defaults.object(forKey: "showExtraUsageIndicators") as? Bool ?? true
        self.appConnectionRevoked = defaults.bool(forKey: Constants.continuitySyncRevokedKey)
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        self.blogUsageSyncEnabled = defaults.object(forKey: "blogUsageSyncEnabled") as? Bool ?? false
        self.blogUsageSyncEndpointURLString = defaults.string(forKey: "blogUsageSyncEndpointURL")
            ?? BlogUsageSyncService.defaultEndpointURLString

        loadCachedSnapshot()
        refreshScheduler.onRefresh = { [weak self] in
            await self?.refresh()
        }
    }
    #else
    init(
        credentialProvider: any CredentialProvider,
        apiService: (any APIServiceProtocol)? = nil,
        usageHistoryService: UsageHistoryService? = nil,
        usageSyncService: any UsageSyncServicing = InactiveUsageSyncService.shared,
        notificationService: any NotificationServiceProtocol = NotificationService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.credentialProvider = credentialProvider
        self.apiService = apiService ?? ClaudeAPIService()
        self.usageSyncService = usageSyncService
        self.usageHistoryService = usageHistoryService ?? UsageHistoryService(defaults: defaults)
        self.defaults = defaults
        self.snapshotStore = UsageSnapshotStore(defaults: defaults)
        self.refreshScheduler = RefreshScheduler(defaults: defaults)
        self.notificationService = notificationService
        self.showExtraUsageIndicators = defaults.object(forKey: "showExtraUsageIndicators") as? Bool ?? true
        self.appConnectionRevoked = defaults.bool(forKey: Constants.continuitySyncRevokedKey)
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")

        loadCachedSnapshot()
        refreshScheduler.onRefresh = { [weak self] in
            await self?.refresh()
        }
    }
    #endif

    // MARK: - Cache Management

    private func loadCachedSnapshot() {
        guard let cached = snapshotStore.load() else { return }
        snapshot = cached.snapshot
        planType = cached.planType
        providerUsage = providerUsageDictionary(from: cached.providerSnapshots)
        isUsingCachedData = true
        Logger.viewModel.debug("Loaded cached snapshot from \(self.timeSinceLastUpdate ?? "unknown time")")
    }

    private func cacheSnapshot(_ snapshot: UsageSnapshot, planType: String) {
        snapshotStore.save(
            snapshot: snapshot,
            planType: planType,
            providerSnapshots: enabledProviderSnapshots(from: providerUsage.values),
            fetchedAt: Date()
        )
        Logger.viewModel.debug("Cached snapshot successfully")
    }

    private func providerUsageDictionary(from snapshots: [ProviderUsageSnapshot]) -> [Provider: ProviderUsageSnapshot] {
        Dictionary(uniqueKeysWithValues: enabledProviderSnapshots(from: snapshots).map { ($0.provider, $0) })
    }

    private func enabledProviderSnapshots(from snapshots: some Sequence<ProviderUsageSnapshot>) -> [ProviderUsageSnapshot] {
        snapshots
            .filter { !Self.disabledProviders.contains($0.provider) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    // MARK: - Notifications

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationTestResult = nil
        guard enabled else {
            notificationsEnabled = false
            return
        }

        let currentState = await notificationService.permissionState()
        notificationPermissionState = currentState

        switch currentState {
        case .authorized:
            notificationsEnabled = true
        case .notDetermined:
            let granted = await notificationService.requestPermission()
            if granted {
                notificationPermissionState = .authorized
                notificationsEnabled = true
            } else {
                notificationPermissionState = await notificationService.permissionState()
                notificationsEnabled = false
            }
        case .denied:
            notificationsEnabled = false
        }
    }

    func refreshNotificationPermissionState() async {
        let currentState = await notificationService.permissionState()
        notificationPermissionState = currentState
        if currentState == .denied {
            notificationsEnabled = false
        }
    }

    func sendTestNotification() async {
        notificationTestResult = await notificationService.sendTestNotification()
        await refreshNotificationPermissionState()
    }

    func clearNotificationTestResult() {
        notificationTestResult = nil
    }

    private func checkUsageNotifications(
        oldSnapshot: UsageSnapshot?,
        newSnapshot: UsageSnapshot
    ) async {
        guard notificationsEnabled else { return }
        await notificationService.checkThresholdCrossings(
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot
        )
    }
}

// MARK: - Refresh Orchestration

enum ClaudeRefreshOutcome: Equatable, Sendable {
    case updated
    case noUsageData
    case skipped
    case failed

    var completedSuccessfully: Bool {
        self == .updated || self == .noUsageData
    }
}

extension UsageViewModel {
    @discardableResult
    func refresh(force: Bool = false) async -> ClaudeRefreshOutcome {
        // Rate limit auto-refresh; a forced refresh (manual) always proceeds.
        if !force,
           let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minRefreshInterval {
            return .skipped
        }
        // Respect an active rate-limit cooldown for auto-refresh so we stop
        // hammering an endpoint that just throttled us. A manual (forced) refresh
        // still proceeds.
        if !force, let until = rateLimitedUntil, Date() < until {
            return .skipped
        }
        // Gate the batch on when it last RAN, not on Claude's success. This keeps the
        // debounce while ensuring Claude's outcome never decides whether the other
        // providers may refresh.
        lastRefreshTime = Date()

        // Fetch each provider concurrently and independently so a slow, retrying, or
        // failing Claude fetch can never delay or block Codex/OpenCode. iOS reads Mac-shared snapshots only.
        #if os(macOS)
        async let claudeArm = refreshClaude()
        // Extra providers share one arm because refreshProviderUsage() reads the
        // tokenSnapshot produced by refreshTokenUsage(); the Codex/OpenCode API fetches
        // inside it are already independent of the Claude API.
        async let providersArm: Void = refreshExtraProviders()
        let (outcome, _) = await (claudeArm, providersArm)
        if !appConnectionRevoked, snapshot != nil || !providerUsage.isEmpty {
            Task { [weak self] in
                await self?.publishContinuitySnapshot()
            }
        }
        Task { await runPassiveBlogUsageSync() }
        return outcome
        #else
        return await refreshClaudeViaSync()
        #endif
    }

    /// Returns the provider-neutral usage snapshot used by provider surfaces.
    /// Claude is bridged from its existing cached snapshot; other providers come
    /// from local macOS services or macOS-published continuity sync.
    func usageSnapshot(for provider: Provider) -> ProviderUsageSnapshot? {
        guard !Self.disabledProviders.contains(provider) else { return nil }
        if provider == .claude {
            return snapshot.map { ProviderUsageSnapshot(claude: $0, planName: planType) }
        }
        return providerUsage[provider]
    }

    /// Providers that have rate-limit data or token-cost detail to present.
    var availableProviders: [Provider] {
        var providers: [Provider] = []
        if snapshot != nil || isNoUsageData {
            providers.append(.claude)
        }
        providers.append(contentsOf: Provider.allCases.filter { provider in
            guard provider != .claude else { return false }
            guard !Self.disabledProviders.contains(provider) else { return false }
            #if os(macOS)
            return usageSnapshot(for: provider) != nil || providerDetails[provider] != nil
            #else
            return usageSnapshot(for: provider) != nil
            #endif
        })
        return providers
    }

    func hasProviderData(_ provider: Provider) -> Bool {
        availableProviders.contains(provider)
    }

    #if os(macOS)
    /// Extra-provider arm: local token usage then Codex/OpenCode rate windows.
    private func refreshExtraProviders() async {
        await refreshTokenUsage()
        await refreshProviderUsage()
    }
    #endif

    /// Fetch the Claude rate-window usage snapshot. Runs as an independent arm of
    /// `refresh()`; its success/failure no longer gates the shared rate-limit timestamp.
    private func refreshClaude() async -> ClaudeRefreshOutcome {
        // API usage fetch (requires network)
        if isOffline {
            if snapshot != nil {
                Logger.viewModel.info("Offline - using cached data")
                isUsingCachedData = true
                errorMessage = nil  // Clear error since we have cached data
            } else {
                errorMessage = "No internet connection and no cached data available."
            }
            return .failed
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        isNoUsageData = false  // Reset on each online fetch attempt

        // Store old snapshot for threshold comparison.
        let oldSnapshot = snapshot

        do {
            let credentials = try await credentialProvider.loadCredentials()
            planType = credentials.planDisplayName
            let newSnapshot = try await apiService.fetchUsage(token: credentials.accessToken)
            snapshot = newSnapshot
            isUsingCachedData = false
            isNoUsageData = false
            #if os(iOS)
            receivedMacSyncedSnapshot = false
            #endif
            rateLimitedUntil = nil  // Successful fetch ends any rate-limit cooldown
            clearIncident(for: .claude)  // Successful fetch ends any active outage

            // Cache the successful response
            cacheSnapshot(newSnapshot, planType: planType)

            // Record to usage history for trend tracking
            await usageHistoryService.record(snapshot: newSnapshot)

            // Check for threshold crossings before platform-specific follow-up work.
            await checkUsageNotifications(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)

            // Cache snapshot for widgets and update Live Activity (iOS only)
            #if os(iOS)
            if let snapshot {
                await WidgetDataManager.shared.save(snapshot)
                await LiveActivityManager.shared.update(snapshot: snapshot)
            }
            #endif
            return .updated
        } catch {
            // "No usage data" is not an error — the usage windows have reset but
            // no prompt has been sent yet. Drop any cached snapshot (it is stale
            // pre-reset data) and show a "No usage data" state in the UI.
            if let apiError = error as? ClaudeAPIService.APIError,
               case .noUsageData = apiError {
                Logger.viewModel.info("No usage data yet (window reset, no prompt sent)")
                snapshot = nil
                isNoUsageData = true
                isUsingCachedData = false
                errorMessage = nil
                clearIncident(for: .claude)
                return .noUsageData
            }

            errorMessage = error.localizedDescription
            // Back off auto-refresh when rate limited so we stop adding to the load.
            if let apiError = error as? ClaudeAPIService.APIError,
               case .rateLimited(let retryAfter) = apiError {
                rateLimitedUntil = Date().addingTimeInterval(retryAfter ?? Constants.rateLimitCooldownFallback)
            }
            // Track service outages (5xx / unavailable); leave any incident
            // untouched for non-outage errors (auth, rate limit, connectivity).
            if Self.isOutageError(error) {
                recordOutage(for: .claude, error: error)
            }
            // Safety net: if the cached snapshot's windows have all expired, the
            // cached data is from before a reset and is now stale. Drop it and
            // show "No usage data" rather than holding onto pre-reset percentages.
            if let cached = snapshot, cached.allWindowsExpired {
                Logger.viewModel.info("Cached snapshot is stale (all windows expired) — showing No usage data")
                snapshot = nil
                isNoUsageData = true
                isUsingCachedData = false
                errorMessage = nil
            } else if snapshot != nil {
                isUsingCachedData = true
                Logger.viewModel.warning("API fetch failed, using cached data: \(error.localizedDescription)")
            }
            return .failed
        }
    }

    #if os(iOS)
    /// iOS refresh reads only the macOS-published snapshot from CloudKit. The Mac
    /// is the source of provider usage updates.
    private func refreshClaudeViaSync() async -> ClaudeRefreshOutcome {
        if appConnectionRevoked {
            errorMessage = nil
            return .skipped
        }

        if isOffline {
            if snapshot != nil {
                isUsingCachedData = true
                errorMessage = nil
            } else {
                errorMessage = "Open \(Constants.appDisplayName) on your Mac to sync usage data."
            }
            return .failed
        }

        if let synced = await usageSyncService.fetchLatest() {
            let oldSnapshot = snapshot
            let hasNewSnapshot = synced.snapshot.map { oldSnapshot?.fetchedAt != $0.fetchedAt } ?? false
            let isCached = synced.age() > Constants.syncFallbackThreshold
            applySyncedSnapshot(synced, isCached: isCached)
            if !isCached, hasNewSnapshot, let newSnapshot = synced.snapshot {
                await checkUsageNotifications(
                    oldSnapshot: oldSnapshot,
                    newSnapshot: newSnapshot
                )
            }
            if !isCached, synced.syncGeneration != nil {
                do {
                    _ = try await usageSyncService.acknowledge(
                        snapshot: synced,
                        from: Self.currentSyncDevice
                    )
                    Logger.viewModel.debug("Acknowledged macOS-synced snapshot")
                } catch {
                    Logger.viewModel.error(
                        "Could not acknowledge macOS-synced snapshot: \(error.localizedDescription)"
                    )
                }
            }
            Logger.viewModel.debug("Applied macOS-synced snapshot (age \(Int(synced.age()))s)")
            return isCached ? .failed : .updated
        }

        if snapshot != nil {
            isUsingCachedData = true
            errorMessage = nil
        } else {
            errorMessage = "Open \(Constants.appDisplayName) on your Mac to share the latest usage."
        }
        Logger.viewModel.info("No fresh macOS-synced snapshot available")
        return .failed
    }

    /// Apply a snapshot received from the Mac: update UI state, persist it so
    /// freshness and offline fallback reflect the Mac's fetch time, and hand it to
    /// the widgets and Live Activity.
    private func applySyncedSnapshot(_ synced: SyncedUsageSnapshot, isCached: Bool = false) {
        if let syncedSnapshot = synced.snapshot {
            snapshot = syncedSnapshot
            planType = synced.planType
        }
        let syncedProviderSnapshots = enabledProviderSnapshots(from: synced.providerSnapshots)
        providerUsage = providerUsageDictionary(from: syncedProviderSnapshots)
        isUsingCachedData = isCached
        isNoUsageData = false
        receivedMacSyncedSnapshot = true
        errorMessage = nil
        rateLimitedUntil = nil
        clearIncident(for: .claude)

        snapshotStore.save(
            snapshot: snapshot,
            planType: synced.planType,
            providerSnapshots: syncedProviderSnapshots,
            fetchedAt: synced.fetchedAt
        )

        Task {
            if let snapshot = synced.snapshot {
                await WidgetDataManager.shared.save(snapshot)
                await LiveActivityManager.shared.update(snapshot: snapshot)
            }
        }
    }
    #endif

    func refreshContinuitySync() async {
        guard !isRefreshingContinuitySync else { return }
        isRefreshingContinuitySync = true
        defer { isRefreshingContinuitySync = false }

        guard !appConnectionRevoked else {
            errorMessage = nil
            return
        }

        #if os(macOS)
        guard snapshot != nil || !providerUsage.isEmpty else {
            continuitySyncErrorMessage = "Refresh usage once before sharing it with iPhone and iPad."
            return
        }
        await publishContinuitySnapshot()
        #else
        _ = await refresh(force: true)
        #endif
    }

    #if os(macOS)
    func refreshContinuityReceipts() async {
        guard publishedSyncGeneration != nil, !isCheckingContinuityReceipts else { return }
        isCheckingContinuityReceipts = true
        defer { isCheckingContinuityReceipts = false }

        do {
            continuityReceipts = try await usageSyncService.fetchReceipts()
            continuitySyncErrorMessage = nil
        } catch {
            continuitySyncErrorMessage = "This Mac shared the latest usage, but could not verify iPhone or iPad: \(error.localizedDescription)"
        }
    }

    private func publishContinuitySnapshot() async {
        publishedSyncGeneration = nil
        continuitySyncErrorMessage = nil

        do {
            let publication = try await usageSyncService.publish(
                snapshot: snapshot,
                planType: planType,
                providerSnapshots: enabledProviderSnapshots(from: providerUsage.values)
            )
            publishedSyncGeneration = publication.syncGeneration
            await refreshContinuityReceipts()
        } catch {
            continuitySyncErrorMessage = "This Mac could not share usage through iCloud: \(error.localizedDescription)"
        }
    }
    #endif

    func revokeAppConnection() async {
        guard !isRevokingAppConnection else { return }
        isRevokingAppConnection = true
        defer { isRevokingAppConnection = false }

        appConnectionRevoked = true
        errorMessage = nil

        #if os(iOS)
        KeychainHelper.deleteCredentials()
        snapshotStore.clear()
        snapshot = nil
        planType = "Free"
        providerUsage.removeAll()
        isUsingCachedData = false
        isNoUsageData = false
        rateLimitedUntil = nil
        activeIncidents.removeAll()
        receivedMacSyncedSnapshot = false
        await WidgetDataManager.shared.clear()
        LiveActivityManager.shared.stop()
        #endif

        #if os(macOS)
        _ = await usageSyncService.revokeAll()
        publishedSyncGeneration = nil
        continuityReceipts = [:]
        continuitySyncErrorMessage = nil
        #else
        _ = await usageSyncService.revoke(device: Self.currentSyncDevice)
        #endif
    }

    func resumeAppConnection() async {
        appConnectionRevoked = false
        await refreshContinuitySync()
    }

    #if os(macOS)
    /// Refresh per-provider detail: Codex rate-limit windows + Claude/Codex/OpenCode
    /// token detail (today/yesterday/30-day, per-model, daily trend).
    private func refreshProviderUsage() async {
        for (provider, service) in providerUsageServices {
            do {
                providerUsage[provider] = try await service.fetchSnapshot()
                clearIncident(for: provider)
            } catch {
                if Self.isOutageError(error) {
                    recordOutage(for: provider, error: error) // Keep cached usage during outages.
                } else {
                    providerUsage[provider] = nil // Preserve hide-on-error behavior.
                }
            }
        }

        providerDetails = await tokenUsageCoordinator.providerDetails(using: tokenSnapshot)
    }

    #endif

    #if os(macOS)
    func loadBlogUsageSyncSettings() async {
        guard let blogUsageSyncService else { return }
        let settings = await blogUsageSyncService.settings()
        blogUsageSyncEnabled = settings.isEnabled
        blogUsageSyncEndpointURLString = settings.endpointURLString
        blogUsageSyncToken = settings.token
        blogUsageSyncStatus = settings.status

        if let blogOAuthService {
            let account = await blogOAuthService.currentAccount()
            isBlogSignedIn = account != nil
            blogOAuthAccountEmail = account?.accountEmail
        }
    }

    /// Run the interactive OAuth sign-in flow, then sync immediately on success.
    func signInToBlog() async {
        guard let blogOAuthService else { return }
        isBlogSigningIn = true
        blogOAuthError = nil
        defer { isBlogSigningIn = false }
        do {
            _ = try await blogOAuthService.signIn()
            await loadBlogUsageSyncSettings()
            await syncBlogUsageNow()
        } catch BlogOAuthError.userCancelled {
            // User dismissed the sign-in sheet; nothing to report.
        } catch {
            blogOAuthError = error.localizedDescription
        }
    }

    func signOutOfBlog() async {
        guard let blogOAuthService else { return }
        blogOAuthError = nil
        do {
            try await blogOAuthService.signOut()
        } catch {
            blogOAuthError = error.localizedDescription
        }
        await loadBlogUsageSyncSettings()
    }

    func saveBlogUsageSyncToken(_ token: String) async {
        guard let blogUsageSyncService else { return }
        await blogUsageSyncService.setToken(token)
        await loadBlogUsageSyncSettings()
    }

    func syncBlogUsageNow() async {
        guard let blogUsageSyncService else { return }
        isBlogUsageSyncing = true
        blogUsageSyncStatus = BlogUsageSyncStatus(
            state: .syncing,
            lastAttemptAt: blogUsageSyncStatus.lastAttemptAt,
            lastSuccessAt: blogUsageSyncStatus.lastSuccessAt,
            message: "Syncing blog usage"
        )
        let status = await blogUsageSyncService.syncNow()
        blogUsageSyncStatus = status
        isBlogUsageSyncing = false
    }

    private func runPassiveBlogUsageSync() async {
        guard let blogUsageSyncService else { return }
        let status = await blogUsageSyncService.syncIfNeeded()
        blogUsageSyncStatus = status
    }

    /// Refresh token usage through the macOS persistence coordinator.
    private func refreshTokenUsage() async {
        isLoadingTokenUsage = true
        tokenUsageError = nil
        defer { isLoadingTokenUsage = false }

        do {
            let update = try await tokenUsageCoordinator.refresh(selectedPeriod: selectedTokenPeriod)
            tokenSnapshot = update.snapshot
            for (period, summary) in update.periodSummaries {
                periodSummaries[period] = summary
            }
            if let selectedSummary = update.selectedPeriodSummary {
                selectedPeriodSummary = selectedSummary
            }
            tokenUsageError = nil
        } catch let error as TokenUsageError {
            tokenUsageError = error
            Logger.tokenUsage.error("Token usage error: \(error.localizedDescription)")
        } catch {
            tokenUsageError = .fileReadError(error)
            Logger.tokenUsage.error("Token usage error: \(error)")
        }
    }

    /// Refresh the summary for the currently selected period (async, non-blocking)
    func refreshSelectedPeriodSummary() async {
        do {
            let summary = try await tokenUsageCoordinator.summary(for: selectedTokenPeriod)
            periodSummaries[selectedTokenPeriod] = summary
            selectedPeriodSummary = summary
        } catch TokenUsageError.repositoryUnavailable {
            return
        } catch {
            // Set error but don't override existing tokenSnapshot
            if tokenUsageError == nil {
                tokenUsageError = .swiftDataError(error)
            }
            Logger.tokenUsage.error("Failed to fetch period summary: \(error)")
        }
    }
    #endif

    func initializeIfNeeded() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        #if os(macOS)
        await loadBlogUsageSyncSettings()
        #endif
        await refresh()
        startAutoRefresh()
    }

    func startAutoRefresh() {
        refreshScheduler.startAutoRefresh()
    }

    func stopAutoRefresh() {
        refreshScheduler.stopAutoRefresh()
    }
}
