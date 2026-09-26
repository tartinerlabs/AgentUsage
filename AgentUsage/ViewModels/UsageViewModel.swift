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

    func ensureSnapshotSubscription() async throws {}

    func deleteSnapshotSubscription() async -> Bool {
        true
    }

    func publishDeviceLedger(_: DeviceUsageLedger) async throws {
        throw unavailableError
    }

    func fetchDeviceLedgers() async -> [DeviceUsageLedger] {
        []
    }

    func deleteDeviceLedger(deviceID _: String) async -> Bool {
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
    /// Rate-limit windows per provider, including Claude dual-written from
    /// `refreshClaude()`. `UsageSnapshot` remains the live Claude API model
    /// and fallback; it is not the only Claude store.
    private(set) var providerUsage: [Provider: ProviderUsageSnapshot] = [:]
    #if os(macOS)
    /// Full per-provider detail (today/yesterday/30-day, per-model, daily trend)
    /// for all providers (Claude, Codex, OpenCode).
    var providerDetails: [Provider: ProviderDetail] = [:]
    /// Daily peak utilization per provider window, backing the usage trends chart.
    private(set) var usageHistory: ProviderUsageHistory = .empty
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
    @ObservationIgnored private var lastPublishedSignature: String?
    @ObservationIgnored private var lastPublishedAt: Date?
    private(set) var continuityReceipts: [UsageSyncDevice: ContinuityReceipt] = [:]
    private(set) var isCheckingContinuityReceipts = false
    /// Identifies this Mac's local usage ledger in Continuity Sync.
    let localDeviceID: String
    @ObservationIgnored private var lastPublishedLedgerSignature: String?
    @ObservationIgnored private var lastPublishedLedgerAt: Date?
    var tokenUsageError: TokenUsageError?
    var isLoadingTokenUsage = false
    #endif
    /// Local token and cost ledgers published by every Mac, this one included.
    private(set) var deviceLedgers: [DeviceUsageLedger] = []
    /// Macs whose ledger removal is in flight, for per-row progress.
    private(set) var removingDeviceIDs: Set<String> = []
    var deviceRemovalErrorMessage: String?
    /// Whose local token and cost usage to show. Quota windows are account-wide.
    var usageSource: UsageSourceSelection = .allMacs {
        didSet {
            defaults.set(usageSource.rawValue, forKey: Self.usageSourceKey)
        }
    }
    private static let usageSourceKey = "usageSource"
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

    // MARK: - Provider Status

    /// The most recent fetch error per provider, cleared on that provider's next success.
    private(set) var providerErrors: [Provider: String] = [:]

    /// Freshness of one provider's data. A rate limit, outage, or failed fetch only
    /// marks the provider it came from, never the whole app.
    func status(for provider: Provider, now: Date = Date()) -> ProviderStatus {
        let usage = usageSnapshot(for: provider)
        if isOffline, usage != nil { return .offline }
        if let until = rateLimitedUntil[provider], now < until { return .rateLimited(until: until) }
        if activeIncidents[provider] != nil { return .serviceDown }
        if let message = providerErrors[provider] { return .failed(message: message) }
        guard let usage else { return .fresh }
        #if os(iOS)
        // Every provider arrives in the same Mac-published payload.
        if isUsingCachedData { return .cached }
        #else
        if provider == .claude, isUsingCachedData { return .cached }
        #endif
        if now.timeIntervalSince(usage.fetchedAt) > Constants.syncFallbackThreshold { return .cached }
        return .fresh
    }

    /// Whether any visible provider is showing data that isn't fresh.
    var hasStaleProviderStatus: Bool {
        availableProviders.contains { status(for: $0) != .fresh }
    }

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
        if let cursorError = error as? CursorUsageService.CursorError {
            switch cursorError {
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

    // MARK: - Rate-limit Cooldown

    /// Whether auto-refresh should skip a provider because it recently returned 429.
    private func isCoolingDown(_ provider: Provider, now: Date = Date()) -> Bool {
        guard let until = rateLimitedUntil[provider] else { return false }
        return now < until
    }

    /// How long to back off after a rate-limit error, or nil if the error isn't a 429.
    nonisolated static func rateLimitCooldown(for error: Error) -> TimeInterval? {
        if let apiError = error as? ClaudeAPIService.APIError,
           case .rateLimited(let retryAfter) = apiError {
            return retryAfter ?? Constants.rateLimitCooldownFallback
        }
        #if os(macOS)
        if let cursorError = error as? CursorUsageService.CursorError,
           case .rateLimited = cursorError {
            return Constants.rateLimitCooldownFallback
        }
        #endif
        return nil
    }

    /// When the snapshot on screen was fetched — by the Mac, for synced data on iOS.
    var lastSyncedAt: Date? {
        snapshotStore.lastSuccessfulFetchTime
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

    /// When auto-refresh fires next; `nil` for Manual, when stopped, or mid-refresh.
    var nextScheduledRefresh: Date? {
        refreshScheduler.nextScheduledRefresh
    }

    var showExtraUsageIndicators: Bool {
        didSet {
            defaults.set(showExtraUsageIndicators, forKey: "showExtraUsageIndicators")
        }
    }

    #if os(iOS)
    /// Opt-in: start a Live Activity when a short rate window hits its limit.
    var autoPinLiveActivityAtLimit: Bool {
        didSet {
            defaults.set(autoPinLiveActivityAtLimit, forKey: "autoPinLiveActivityAtLimit")
        }
    }

    private var isSceneActive = false
    #endif

    private(set) var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    private(set) var notificationPermissionState: NotificationPermissionState = .notDetermined
    private(set) var notificationTestResult: NotificationTestResult?

    #if os(macOS)
    /// Pinnable providers in `availableProviders` order (newest local session first),
    /// so the compact strip's provider cap keeps the most recently used tools.
    var menuBarProviders: [Provider] {
        availableProviders.filter { MenuBarSettingsManager.supportedProviders.contains($0) }
    }

    /// How many providers the compact strip may show at once, most recently used first.
    var menuBarMaximumProviders: Int {
        get { menuBarSettingsManager.maximumProviders }
        set { menuBarSettingsManager.maximumProviders = newValue }
    }

    func menuBarWindowOptions(for provider: Provider) -> [MenuBarWindowOption] {
        MenuBarSettingsManager.windowOptions(
            snapshot: usageSnapshot(for: provider),
            pinned: menuBarPinnedWindows(for: provider)
        )
    }

    func menuBarPinnedWindows(for provider: Provider) -> [UsageWindowID] {
        menuBarSettingsManager.pinnedWindows(for: provider)
    }

    func isMenuBarWindowPinned(_ window: UsageWindowID, for provider: Provider) -> Bool {
        menuBarSettingsManager.isPinned(window, for: provider)
    }

    func canPinMenuBarWindow(_ window: UsageWindowID, for provider: Provider) -> Bool {
        menuBarSettingsManager.canPin(window, for: provider)
    }

    func setMenuBarWindowPinned(
        _ window: UsageWindowID,
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
    #if os(iOS)
    let liveActivityManager: LiveActivityManager
    #endif

    /// Providers the user turned off in Settings (macOS). They are never fetched,
    /// shown, or shared over Continuity Sync. Always empty on iPhone and iPad, which
    /// follow whatever the Mac publishes.
    private(set) var userDisabledProviders: Set<Provider>

    /// Unshipped providers plus the ones the user turned off: the single choke
    /// point every provider surface filters through.
    var disabledProviders: Set<Provider> {
        ProviderSettings.unshippedProviders.union(userDisabledProviders)
    }

    func isProviderEnabled(_ provider: Provider) -> Bool {
        !disabledProviders.contains(provider)
    }

    #if os(macOS)
    private let tokenUsageCoordinator: any TokenUsageCoordinating
    private let menuBarSettingsManager: MenuBarSettingsManager
    private let providerUsageServices: [Provider: any ProviderUsageServiceProtocol]
    #endif
    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 30
    private var hasInitialized = false

    /// Per-provider cooldown after an HTTP 429. While a provider's date is in the future,
    /// auto-refresh skips that provider only — the others keep refreshing. Cleared on the
    /// provider's next successful fetch. Persisted so a relaunch doesn't skip the
    /// cooldown and immediately hit the endpoint again.
    private var rateLimitedUntil: [Provider: Date] = [:] {
        didSet {
            guard rateLimitedUntil != oldValue else { return }
            let stored = Dictionary(uniqueKeysWithValues: rateLimitedUntil.map { ($0.key.rawValue, $0.value) })
            defaults.set(stored, forKey: Self.rateLimitedUntilKey)
        }
    }
    private static let rateLimitedUntilKey = "providerRateLimitedUntil"
    private static let legacyClaudeRateLimitedUntilKey = "claudeRateLimitedUntil"

    private static func loadRateLimitedUntil(from defaults: UserDefaults) -> [Provider: Date] {
        let stored = defaults.dictionary(forKey: rateLimitedUntilKey) as? [String: Date] ?? [:]
        var cooldowns = Dictionary(uniqueKeysWithValues: stored.compactMap { key, date in
            Provider(rawValue: key).map { ($0, date) }
        })
        // Carry over a cooldown written before cooldowns were per provider.
        if let legacy = defaults.object(forKey: legacyClaudeRateLimitedUntilKey) as? Date {
            cooldowns[.claude] = cooldowns[.claude] ?? legacy
            defaults.removeObject(forKey: legacyClaudeRateLimitedUntilKey)
        }
        return cooldowns
    }

    /// Overall status computed from the worst status across every provider's windows,
    /// not Claude's alone — a single app-wide indicator must reflect Codex too.
    var overallStatus: UsageStatus {
        UsageCalculations.overallStatus(
            from: isProviderEnabled(.claude) ? snapshot : nil,
            providerSnapshots: enabledProviderSnapshots(from: providerUsage.values)
        )
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
        // Any provider's data counts: Claude can be turned off in Settings.
        if snapshot != nil || !availableProviders.isEmpty || isNoUsageData {
            return .waitingForDevices(message: nil)
        }
        #else
        if !availableProviderSnapshots.isEmpty || isNoUsageData {
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
        guard publishedSyncGeneration != nil else { return false }
        return continuityReceipts.values.contains(where: receiptConfirmsCurrentPublish)
    }

    /// Another Mac can publish after this one, and iPhone then acknowledges that
    /// newer generation instead. A receipt written at or after this Mac's publish
    /// still proves the round trip works.
    private func receiptConfirmsCurrentPublish(_ receipt: ContinuityReceipt) -> Bool {
        guard let publishedSyncGeneration else { return false }
        if receipt.syncGeneration == publishedSyncGeneration { return true }
        guard let lastPublishedAt else { return false }
        return receipt.acknowledgedAt >= lastPublishedAt
    }

    private func continuityNodeState(for device: UsageSyncDevice) -> ContinuityNodeState {
        guard let receipt = continuityReceipts[device] else {
            return isCheckingContinuityReceipts ? .checking : .unavailable
        }
        guard receiptConfirmsCurrentPublish(receipt) else {
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
        self.providerUsageServices = providerUsageServices
        self.localDeviceID = LocalDeviceIdentity.deviceID(defaults: defaults)
        self.showExtraUsageIndicators = defaults.object(forKey: "showExtraUsageIndicators") as? Bool ?? true
        self.appConnectionRevoked = defaults.bool(forKey: Constants.continuitySyncRevokedKey)
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        self.rateLimitedUntil = Self.loadRateLimitedUntil(from: defaults)
        self.usageSource = defaults.string(forKey: Self.usageSourceKey)
            .flatMap(UsageSourceSelection.init(rawValue:)) ?? .allMacs
        self.userDisabledProviders = ProviderSettings.userDisabledProviders(defaults: defaults)

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
        liveActivityManager: LiveActivityManager? = nil,
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
        self.liveActivityManager = liveActivityManager ?? .shared
        self.showExtraUsageIndicators = defaults.object(forKey: "showExtraUsageIndicators") as? Bool ?? true
        self.autoPinLiveActivityAtLimit = defaults.bool(forKey: "autoPinLiveActivityAtLimit")
        self.appConnectionRevoked = defaults.bool(forKey: Constants.continuitySyncRevokedKey)
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        self.rateLimitedUntil = Self.loadRateLimitedUntil(from: defaults)
        self.usageSource = defaults.string(forKey: Self.usageSourceKey)
            .flatMap(UsageSourceSelection.init(rawValue:)) ?? .allMacs
        // Provider settings live on the Mac; the synced payload already leaves
        // out anything turned off there.
        self.userDisabledProviders = []

        loadCachedSnapshot()
        refreshScheduler.onRefresh = { [weak self] in
            await self?.refresh()
        }
    }
    #endif

    // MARK: - Cache Management

    private func loadCachedSnapshot() {
        guard let cached = snapshotStore.load() else { return }
        snapshot = isProviderEnabled(.claude) ? cached.snapshot : nil
        planType = cached.planType
        providerUsage = providerUsageDictionary(from: cached.providerSnapshots)
        // Older caches stored Claude only as `UsageSnapshot`.
        if providerUsage[.claude] == nil, let snapshot {
            providerUsage[.claude] = ClaudeAPIService.providerSnapshot(
                from: snapshot,
                planName: planType
            )
        }
        #if os(macOS)
        providerDetails = addingUnavailableLocalUsageDetails(
            to: [:],
            from: providerUsage.values
        )
        #endif
        isUsingCachedData = true
        Logger.viewModel.debug("Loaded cached snapshot from \(self.timeSinceLastUpdate ?? "unknown time")")
    }

    private func cacheSnapshot(_ snapshot: UsageSnapshot?, planType: String) {
        #if os(macOS)
        let providerSnapshots = continuityProviderSnapshots()
        #else
        let providerSnapshots = enabledProviderSnapshots(from: providerUsage.values)
        #endif
        let fetchedAt = ([snapshot?.fetchedAt] + providerSnapshots.map { Optional($0.fetchedAt) })
            .compactMap { $0 }
            .max() ?? Date()
        snapshotStore.save(
            snapshot: snapshot,
            planType: planType,
            providerSnapshots: providerSnapshots,
            fetchedAt: fetchedAt
        )
        Logger.viewModel.debug("Cached snapshot successfully")
    }

    private func providerUsageDictionary(from snapshots: [ProviderUsageSnapshot]) -> [Provider: ProviderUsageSnapshot] {
        Dictionary(uniqueKeysWithValues: enabledProviderSnapshots(from: snapshots).map { ($0.provider, $0) })
    }

    private func enabledProviderSnapshots(from snapshots: some Sequence<ProviderUsageSnapshot>) -> [ProviderUsageSnapshot] {
        snapshots
            .filter { !disabledProviders.contains($0.provider) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    #if os(macOS)
    private func addingUnavailableLocalUsageDetails(
        to details: [Provider: ProviderDetail],
        from snapshots: some Sequence<ProviderUsageSnapshot>
    ) -> [Provider: ProviderDetail] {
        var resolved = details
        for providerSnapshot in snapshots {
            let provider = providerSnapshot.provider
            guard resolved[provider] == nil,
                  provider.supports(.tokenCost) || !providerSnapshot.effortSummaries.isEmpty
            else {
                continue
            }

            let previousEffort = providerDetails[provider]?.effortSummaries ?? []
            resolved[provider] = Self.unavailableLocalUsageDetail(
                effortSummaries: previousEffort.isEmpty
                    ? providerSnapshot.effortSummaries
                    : previousEffort,
                lastUsedAt: providerSnapshot.lastUsedAt
            )
        }
        return resolved
    }

    private static func unavailableLocalUsageDetail(
        effortSummaries: [EffortPeriodSummary],
        lastUsedAt: Date? = nil
    ) -> ProviderDetail {
        let zeroToday = TokenUsageSummary(tokens: .zero, costUSD: 0, period: .today)
        return ProviderDetail(
            today: zeroToday,
            yesterday: zeroToday,
            last30Days: TokenUsageSummary(tokens: .zero, costUSD: 0, period: .last30Days),
            byModel: [:],
            dailyCosts: [],
            effortSummaries: effortSummaries,
            hasTokenUsage: false,
            lastUsedAt: lastUsedAt
        )
    }
    #endif

    // MARK: - Provider Settings

    #if os(macOS)
    /// Whether this Mac has anything to share over Continuity Sync yet.
    var hasContinuityPayload: Bool {
        snapshot != nil || !providerUsage.isEmpty || !providersWithEffortUsage.isEmpty
    }

    /// Whether the Settings toggle for `provider` may be switched off: at least
    /// one provider must stay enabled.
    func canDisableProvider(_ provider: Provider) -> Bool {
        ProviderSettings.canDisable(provider, userDisabled: userDisabledProviders)
    }

    /// Turn a provider on or off. A provider turned off stops being fetched,
    /// disappears from every Mac surface, and is withdrawn from Continuity Sync;
    /// turning it back on fetches it right away.
    func setProviderEnabled(_ provider: Provider, enabled: Bool) async {
        let updated = ProviderSettings.setEnabled(enabled, for: provider, defaults: defaults)
        guard updated != userDisabledProviders else { return }
        userDisabledProviders = updated
        removeDisabledProviderState()

        if enabled {
            await refresh(force: true)
            // Share it right away, as turning a provider off does, rather than
            // waiting for the automatic publish spacing.
            if !appConnectionRevoked {
                await publishContinuitySnapshot(force: true)
                await syncDeviceLedgers(force: true)
            }
            return
        }

        usageHistory = enabledHistory(usageHistory)
        cacheSnapshot(snapshot, planType: planType)
        if !appConnectionRevoked {
            // A settings change is a deliberate action, like a manual share, so it
            // publishes now rather than waiting for the automatic spacing.
            await publishContinuitySnapshot(force: true)
            await syncDeviceLedgers(force: true, removesEmptyLedger: true)
        }
        await armResetNotifications()
    }

    private func enabledHistory(_ history: ProviderUsageHistory) -> ProviderUsageHistory {
        let disabled = disabledProviders
        guard history.peaks.contains(where: { disabled.contains($0.provider) }) else { return history }
        return ProviderUsageHistory(peaks: history.peaks.filter { !disabled.contains($0.provider) })
    }

    /// Forget every piece of state held for providers that are now disabled, so no
    /// stale data, error, or outage lingers until the next relaunch.
    private func removeDisabledProviderState() {
        let disabled = disabledProviders
        for provider in disabled {
            providerUsage[provider] = nil
            providerErrors[provider] = nil
            activeIncidents[provider] = nil
        }
        providerDetails = providerDetails.filter { !disabled.contains($0.key) }
        if disabled.contains(.claude) {
            snapshot = nil
            isNoUsageData = false
            isUsingCachedData = false
            errorMessage = nil
            clearClaudeTokenUsage()
        }
    }
    #endif

    // MARK: - Notifications

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationTestResult = nil
        guard enabled else {
            notificationsEnabled = false
            await notificationService.cancelResetNotifications()
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

        if notificationsEnabled {
            await armResetNotifications()
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

    func setNotifyOnReset(_ enabled: Bool) async {
        var settings = NotificationSettings.load(defaults: defaults)
        settings.notifyOnReset = enabled
        settings.save(defaults: defaults)
        if enabled {
            await armResetNotifications()
        } else {
            await notificationService.cancelResetNotifications()
        }
    }

    private func checkUsageNotifications(
        oldSnapshot: ProviderUsageSnapshot?,
        newSnapshot: ProviderUsageSnapshot
    ) async {
        guard notificationsEnabled else { return }
        await notificationService.checkThresholdCrossings(
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot
        )
    }

    private func armResetNotifications() async {
        guard notificationsEnabled else {
            await notificationService.cancelResetNotifications()
            return
        }
        await notificationService.armResetNotifications(
            from: availableProviderSnapshots,
            now: Date()
        )
    }

    #if os(iOS)
    func handleScenePhase(_ phase: ScenePhase) async {
        isSceneActive = phase == .active
        if phase == .active {
            await reconcileLiveActivity()
        }
    }

    func setAutoPinLiveActivityAtLimit(_ enabled: Bool) async {
        autoPinLiveActivityAtLimit = enabled
        if enabled {
            liveActivityManager.clearDismissals()
        }
        await reconcileLiveActivity()
    }

    private func reconcileLiveActivity() async {
        await liveActivityManager.reconcile(
            from: availableProviderSnapshots,
            autoPinAtLimit: autoPinLiveActivityAtLimit,
            canStart: isSceneActive
        )
    }
    #endif
}

// MARK: - Refresh Orchestration

enum ClaudeRefreshOutcome: Equatable, Sendable {
    case updated
    case noUsageData
    case skipped
    case failed
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
        // Rate-limit cooldowns are per provider and checked inside each arm, so a
        // throttled Claude endpoint never stops Codex, Cursor, or Grok from refreshing.
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
        // Both arms record into history, so reload once they have both landed.
        usageHistory = enabledHistory(await usageHistoryService.getProviderHistory())
        // Persist the enriched provider payload after local log aggregation has
        // finished so effort summaries survive a relaunch before the next refresh.
        cacheSnapshot(snapshot, planType: planType)
        if !appConnectionRevoked,
           snapshot != nil || !providerUsage.isEmpty || !providersWithEffortUsage.isEmpty {
            Task { [weak self] in
                await self?.publishContinuitySnapshot(force: false)
                await self?.syncDeviceLedgers(force: false)
            }
        }
        await armResetNotifications()
        return outcome
        #else
        return await refreshClaudeViaSync()
        #endif
    }

    /// Returns the provider-neutral usage snapshot used by provider surfaces.
    /// Claude prefers the dual-written `providerUsage[.claude]` entry and falls
    /// back to bridging `UsageSnapshot`. Other providers come from local macOS
    /// services or macOS-published continuity sync.
    func usageSnapshot(for provider: Provider) -> ProviderUsageSnapshot? {
        guard !disabledProviders.contains(provider) else { return nil }
        if provider == .claude {
            if let stored = providerUsage[.claude] {
                return overlayingLocalUsage(on: stored, planName: planType)
            }
            #if os(macOS)
            if let snapshot {
                return overlayingLocalUsage(
                    on: ClaudeAPIService.providerSnapshot(
                        from: snapshot,
                        planName: planType,
                        effortSummaries: providerDetails[.claude]?.effortSummaries ?? [],
                        lastUsedAt: providerDetails[.claude]?.lastUsedAt
                    )
                )
            }
            #endif
            return snapshot.map {
                overlayingLocalUsage(
                    on: ClaudeAPIService.providerSnapshot(from: $0, planName: planType)
                )
            }
        }
        return providerUsage[provider].map { overlayingLocalUsage(on: $0) }
    }

    private func overlayingLocalUsage(
        on snapshot: ProviderUsageSnapshot,
        planName: String? = nil
    ) -> ProviderUsageSnapshot {
        #if os(macOS)
        let effortSummaries = providerDetails[snapshot.provider]?.effortSummaries
            ?? snapshot.effortSummaries
        let lastUsedAt = providerDetails[snapshot.provider]?.lastUsedAt ?? snapshot.lastUsedAt
        #else
        let effortSummaries = snapshot.effortSummaries
        let lastUsedAt = snapshot.lastUsedAt
        #endif
        let resolvedPlanName = planName ?? snapshot.planName
        if effortSummaries == snapshot.effortSummaries,
           lastUsedAt == snapshot.lastUsedAt,
           resolvedPlanName == snapshot.planName {
            return snapshot
        }
        return ProviderUsageSnapshot(
            provider: snapshot.provider,
            windows: snapshot.windows,
            extraUsage: snapshot.extraUsage,
            planName: resolvedPlanName,
            rateLimitResetCredits: snapshot.rateLimitResetCredits,
            creditBalance: snapshot.creditBalance,
            effortSummaries: effortSummaries,
            fetchedAt: snapshot.fetchedAt,
            lastUsedAt: lastUsedAt
        )
    }

    /// Session effort distribution for the Macs `usageSource` selects: this Mac's
    /// own logs or other Macs' ledgers on macOS, synced ledgers or snapshot on iOS.
    func effortSummary(for provider: Provider, period: EffortPeriod) -> EffortPeriodSummary? {
        // Published ledgers are per Mac; the synced snapshot's effort is only
        // whichever Mac published last, so it must not stand in for them.
        if usesDeviceLedgerUsage {
            return providerDetail(for: provider)?.effortSummary(for: period)
        }
        #if os(macOS)
        if let summary = providerDetails[provider]?.effortSummary(for: period) {
            return summary
        }
        #endif
        return providerUsage[provider]?.effortSummary(for: period)
    }

    /// Effort distributions for the Macs `usageSource` selects, one per period.
    func effortSummaries(for provider: Provider) -> [EffortPeriodSummary] {
        EffortPeriod.allCases.compactMap { effortSummary(for: provider, period: $0) }
    }

    /// Whether token, cost, and effort detail come from published ledgers
    /// rather than this Mac's own logs (macOS) or the synced snapshot (iOS).
    private var usesDeviceLedgerUsage: Bool {
        #if os(macOS)
        if case .mac(let id) = effectiveUsageSource, id == localDeviceID { return false }
        return deviceLedgers.contains { $0.deviceID != localDeviceID }
        #else
        return !deviceLedgers.isEmpty
        #endif
    }

    /// Providers with at least one classified or explicitly unclassified effort session.
    var providersWithEffortUsage: [Provider] {
        Provider.allCases.filter { provider in
            guard !disabledProviders.contains(provider) else { return false }
            return EffortPeriod.allCases.contains { period in
                (effortSummary(for: provider, period: period)?.totalSessionCount ?? 0) > 0
            }
        }
    }

    /// Providers that have rate-limit data or token-cost detail to present.
    ///
    /// Newest local session first. Equal or unknown activity falls through to
    /// hottest live window (higher % used, then sooner reset), then canonical
    /// `Provider` order.
    var availableProviders: [Provider] {
        let members = Provider.allCases.filter { provider in
            guard !disabledProviders.contains(provider) else { return false }
            if usageSnapshot(for: provider) != nil { return true }
            #if os(macOS)
            if let detail = providerDetails[provider] {
                return detail.hasTokenUsage || !detail.effortSummaries.isEmpty
            }
            #endif
            return false
        }
        let now = Date()
        return members.sorted { lhs, rhs in
            UsageActivitySelection.precedesByRecency(
                lhsUsedAt: lastUsedAt(for: lhs),
                lhsWindow: usageSnapshot(for: lhs)?.hottestLiveWindow(now: now),
                lhsProvider: lhs,
                rhsUsedAt: lastUsedAt(for: rhs),
                rhsWindow: usageSnapshot(for: rhs)?.hottestLiveWindow(now: now),
                rhsProvider: rhs
            )
        }
    }

    private func lastUsedAt(for provider: Provider) -> Date? {
        if let used = usageSnapshot(for: provider)?.lastUsedAt {
            return used
        }
        #if os(macOS)
        return providerDetails[provider]?.lastUsedAt
        #else
        return nil
        #endif
    }

    /// Provider snapshots in the same recency order as `availableProviders`.
    var availableProviderSnapshots: [ProviderUsageSnapshot] {
        availableProviders.compactMap { usageSnapshot(for: $0) }
    }

    func hasProviderData(_ provider: Provider) -> Bool {
        availableProviders.contains(provider)
    }

    /// Token/trend/model/effort detail from local logs, for the Macs
    /// `usageSource` selects. On macOS this Mac's own detail comes from its live local
    /// refresh; other Macs come from their published ledgers.
    func providerDetail(for provider: Provider) -> ProviderDetail? {
        guard isProviderEnabled(provider) else { return nil }
        #if os(macOS)
        let local = providerDetails[provider]
        let remote = deviceLedgers.filter { $0.deviceID != localDeviceID }
        switch effectiveUsageSource {
        case .mac(let id) where id == localDeviceID:
            return local
        case .mac(let id):
            return DeviceUsageMerge.detail(for: provider, from: remote.filter { $0.deviceID == id })
        case .allMacs:
            guard !remote.isEmpty else { return local }
            let localLedger = DeviceUsageMerge.ledger(
                deviceID: localDeviceID,
                deviceName: "",
                details: providerDetails
            )
            return DeviceUsageMerge.detail(for: provider, from: remote + [localLedger])
        }
        #else
        switch effectiveUsageSource {
        case .allMacs:
            return DeviceUsageMerge.detail(for: provider, from: deviceLedgers)
        case .mac(let id):
            return DeviceUsageMerge.detail(
                for: provider,
                from: deviceLedgers.filter { $0.deviceID == id }
            )
        }
        #endif
    }

    /// "All Macs", then each Mac with published usage. On macOS this Mac is
    /// listed first even before its own ledger has synced.
    var usageSourceOptions: [UsageSourceOption] {
        var macs: [UsageSourceOption] = []
        #if os(macOS)
        macs.append(UsageSourceOption(selection: .mac(id: localDeviceID), title: "This Mac"))
        #endif
        let others = deviceLedgers.sorted {
            $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending
        }
        for ledger in others {
            #if os(macOS)
            if ledger.deviceID == localDeviceID { continue }
            #endif
            macs.append(UsageSourceOption(selection: .mac(id: ledger.deviceID), title: ledger.deviceName))
        }
        return [UsageSourceOption(selection: .allMacs, title: "All Macs")] + macs
    }

    /// Macs that can be removed from here, newest first. On macOS this Mac is
    /// left out: it would publish its ledger again on the next refresh.
    var removableDeviceLedgers: [DeviceUsageLedger] {
        deviceLedgers
            .filter { ledger in
                #if os(macOS)
                return ledger.deviceID != localDeviceID
                #else
                return true
                #endif
            }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Remove a Mac's shared usage, e.g. one that no longer runs AgentUsage. A
    /// Mac that is still active publishes its usage again on its next refresh.
    func removeDevice(_ ledger: DeviceUsageLedger) async {
        guard !removingDeviceIDs.contains(ledger.deviceID) else { return }
        removingDeviceIDs.insert(ledger.deviceID)
        defer { removingDeviceIDs.remove(ledger.deviceID) }
        deviceRemovalErrorMessage = nil

        if await usageSyncService.deleteDeviceLedger(deviceID: ledger.deviceID) {
            deviceLedgers.removeAll { $0.deviceID == ledger.deviceID }
        } else {
            deviceRemovalErrorMessage = "Could not remove \(ledger.deviceName). Check your iCloud connection and try again."
        }
    }

    /// Only offered once there is more than one Mac to choose from.
    var showsUsageSourcePicker: Bool {
        usageSourceOptions.count > 2
    }

    /// The stored choice, or All Macs when that Mac no longer publishes.
    var effectiveUsageSource: UsageSourceSelection {
        guard case .mac(let id) = usageSource else { return .allMacs }
        #if os(macOS)
        if id == localDeviceID { return usageSource }
        #endif
        return deviceLedgers.contains { $0.deviceID == id } ? usageSource : .allMacs
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
        // Claude turned off in Settings: no credential read, no API call.
        guard isProviderEnabled(.claude) else { return .skipped }

        // Respect an active rate-limit cooldown for every refresh, manual included:
        // the endpoint will refuse the request, and hitting it again can extend the
        // cooldown. Other providers still refresh. Re-surface the countdown so a
        // manual refresh visibly explains why Claude didn't update.
        if let until = rateLimitedUntil[.claude], Date() < until {
            let remaining = until.timeIntervalSinceNow.rounded(.up)
            errorMessage = ClaudeAPIService.APIError.rateLimited(retryAfter: remaining).localizedDescription
            isUsingCachedData = snapshot != nil
            return .skipped
        }

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
            // Claude may have been turned off while the request was in flight.
            guard isProviderEnabled(.claude) else { return .skipped }
            snapshot = newSnapshot
            isUsingCachedData = false
            isNoUsageData = false
            #if os(iOS)
            receivedMacSyncedSnapshot = false
            #endif
            rateLimitedUntil[.claude] = nil  // Successful fetch ends any rate-limit cooldown
            providerErrors[.claude] = nil
            clearIncident(for: .claude)  // Successful fetch ends any active outage

            #if os(macOS)
            let effortSummaries = providerDetails[.claude]?.effortSummaries
                ?? providerUsage[.claude]?.effortSummaries
                ?? []
            let lastUsedAt = providerDetails[.claude]?.lastUsedAt
                ?? providerUsage[.claude]?.lastUsedAt
            #else
            let effortSummaries = providerUsage[.claude]?.effortSummaries ?? []
            let lastUsedAt = providerUsage[.claude]?.lastUsedAt
            #endif
            providerUsage[.claude] = ClaudeAPIService.providerSnapshot(
                from: newSnapshot,
                planName: planType,
                effortSummaries: effortSummaries,
                lastUsedAt: lastUsedAt
            )

            // Cache the successful response
            cacheSnapshot(newSnapshot, planType: planType)

            // Record to usage history for trend tracking
            await usageHistoryService.record(snapshot: newSnapshot)

            // Check for threshold crossings before platform-specific follow-up work.
            if let newProviderSnapshot = providerUsage[.claude] {
                await checkUsageNotifications(
                    oldSnapshot: oldSnapshot.map { ClaudeAPIService.providerSnapshot(from: $0) },
                    newSnapshot: newProviderSnapshot
                )
            }

            // Cache every provider for widgets and update Live Activity (iOS only).
            #if os(iOS)
            let widgetSnapshots = availableProviderSnapshots
            if widgetSnapshots.isEmpty {
                await WidgetDataManager.shared.clear()
            } else {
                await WidgetDataManager.shared.save(widgetSnapshots)
            }
            await reconcileLiveActivity()
            #endif
            return .updated
        } catch {
            // Claude was turned off while the request was in flight; its error is moot.
            guard isProviderEnabled(.claude) else { return .skipped }
            // "No usage data" is not an error — the usage windows have reset but
            // no prompt has been sent yet. Drop any cached snapshot (it is stale
            // pre-reset data) and show a "No usage data" state in the UI.
            if let apiError = error as? ClaudeAPIService.APIError,
               case .noUsageData = apiError {
                Logger.viewModel.info("No usage data yet (window reset, no prompt sent)")
                snapshot = nil
                providerUsage[.claude] = nil
                isNoUsageData = true
                isUsingCachedData = false
                errorMessage = nil
                providerErrors[.claude] = nil
                clearIncident(for: .claude)
                return .noUsageData
            }

            errorMessage = error.localizedDescription
            providerErrors[.claude] = error.localizedDescription
            // Back off auto-refresh when rate limited so we stop adding to the load.
            if let cooldown = Self.rateLimitCooldown(for: error) {
                rateLimitedUntil[.claude] = Date().addingTimeInterval(cooldown)
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
                providerUsage[.claude] = nil
                isNoUsageData = true
                isUsingCachedData = false
                errorMessage = nil
                providerErrors[.claude] = nil
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
            if !availableProviderSnapshots.isEmpty {
                isUsingCachedData = true
                errorMessage = nil
            } else {
                errorMessage = "Open \(Constants.appDisplayName) on your Mac to sync usage data."
            }
            return .failed
        }

        isLoading = true
        defer { isLoading = false }

        if let synced = await usageSyncService.fetchLatest() {
            let oldSnapshot = snapshot
            // Another Mac can overwrite the shared record with an older fetch. Applying
            // it would lower the baseline, and the next fresh snapshot would re-alert
            // every threshold between the two.
            if let oldFetchedAt = oldSnapshot?.fetchedAt,
               let newFetchedAt = synced.snapshot?.fetchedAt,
               newFetchedAt < oldFetchedAt {
                Logger.viewModel.info("Ignored a macOS-synced snapshot older than the current one")
                isUsingCachedData = Date().timeIntervalSince(oldFetchedAt) > Constants.syncFallbackThreshold
                errorMessage = nil
                return .skipped
            }
            let oldProviderSnapshots = Dictionary(
                uniqueKeysWithValues: availableProviderSnapshots.map { ($0.provider, $0) }
            )
            let isCached = synced.age() > Constants.syncFallbackThreshold
            await applySyncedSnapshot(synced, isCached: isCached)
            if !isCached {
                // Each provider is fetched on its own schedule; only evaluate the ones
                // this record actually refreshed.
                for newSnapshot in availableProviderSnapshots {
                    let old = oldProviderSnapshots[newSnapshot.provider]
                    if let old, newSnapshot.fetchedAt <= old.fetchedAt { continue }
                    await checkUsageNotifications(oldSnapshot: old, newSnapshot: newSnapshot)
                }
            }
            if !isCached, synced.syncGeneration != nil {
                do {
                    _ = try await usageSyncService.acknowledge(
                        snapshot: synced,
                        from: Self.currentSyncDevice
                    )
                    Logger.viewModel.debug("Acknowledged macOS-synced snapshot")
                    await ensureSilentPushSubscription()
                } catch {
                    Logger.viewModel.error(
                        "Could not acknowledge macOS-synced snapshot: \(error.localizedDescription)"
                    )
                }
            }
            deviceLedgers = await usageSyncService.fetchDeviceLedgers()
            Logger.viewModel.debug("Applied macOS-synced snapshot (age \(Int(synced.age()))s)")
            return isCached ? .failed : .updated
        }

        if !availableProviderSnapshots.isEmpty {
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
    private func applySyncedSnapshot(_ synced: SyncedUsageSnapshot, isCached: Bool = false) async {
        // A sync record is a full provider payload. `nil` means Claude has no
        // quota snapshot, including when the record contains effort data only.
        snapshot = synced.snapshot
        planType = synced.planType
        let syncedProviderSnapshots = enabledProviderSnapshots(from: synced.providerSnapshots)
        providerUsage = providerUsageDictionary(from: syncedProviderSnapshots)
        isUsingCachedData = isCached
        isNoUsageData = false
        receivedMacSyncedSnapshot = true
        errorMessage = nil
        rateLimitedUntil.removeAll()
        clearIncident(for: .claude)

        snapshotStore.save(
            snapshot: snapshot,
            planType: planType,
            providerSnapshots: syncedProviderSnapshots,
            fetchedAt: synced.fetchedAt
        )

        let widgetSnapshots = availableProviderSnapshots
        if widgetSnapshots.isEmpty {
            await WidgetDataManager.shared.clear()
        } else {
            await WidgetDataManager.shared.save(widgetSnapshots)
        }
        await reconcileLiveActivity()
        await armResetNotifications()
    }

    /// Start the sync engine that owns the CloudKit silent-push subscription.
    /// Called at process start so background launches can receive pushes, and
    /// again after a verified Mac snapshot. Failures are logged; BGAppRefresh
    /// remains the floor.
    func ensureSilentPushSubscription() async {
        guard !appConnectionRevoked else { return }
        do {
            try await usageSyncService.ensureSnapshotSubscription()
        } catch {
            Logger.viewModel.error(
                "Could not register CloudKit silent-push subscription: \(error.localizedDescription)"
            )
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
        guard hasContinuityPayload else {
            continuitySyncErrorMessage = "Refresh usage once before sharing it with iPhone and iPad."
            return
        }
        await publishContinuitySnapshot(force: true)
        await syncDeviceLedgers(force: true)
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

    /// Every publish costs the iPhone one silent push, and iOS stops delivering
    /// them when they arrive too often. Automatic publishes therefore go out only
    /// when a displayed value changed, spaced apart, plus a slow heartbeat that
    /// keeps the shared snapshot's fetch time fresh. Manual shares always publish.
    private static let minimumPublishSpacing: TimeInterval = 5 * 60
    private static let publishHeartbeat: TimeInterval = 30 * 60

    private func publishContinuitySnapshot(force: Bool) async {
        let providerSnapshots = continuityProviderSnapshots()
        let signature = Self.publishSignature(planType: planType, providerSnapshots: providerSnapshots)
        if !force, let lastPublishedAt, publishedSyncGeneration != nil {
            let elapsed = Date().timeIntervalSince(lastPublishedAt)
            let required = signature == lastPublishedSignature
                ? Self.publishHeartbeat
                : Self.minimumPublishSpacing
            if elapsed < required {
                await refreshContinuityReceipts()
                return
            }
        }

        publishedSyncGeneration = nil
        continuitySyncErrorMessage = nil

        do {
            let publication = try await usageSyncService.publish(
                snapshot: isProviderEnabled(.claude) ? snapshot : nil,
                planType: planType,
                providerSnapshots: providerSnapshots
            )
            publishedSyncGeneration = publication.syncGeneration
            lastPublishedSignature = signature
            lastPublishedAt = Date()
            await refreshContinuityReceipts()
        } catch {
            continuitySyncErrorMessage = "This Mac could not share usage through iCloud: \(error.localizedDescription)"
        }
    }

    /// Ledgers change with every request logged, so they follow the same
    /// spacing and heartbeat as snapshot publishes to keep silent pushes rare.
    private static let ledgerPublishSpacing: TimeInterval = 5 * 60
    private static let ledgerPublishHeartbeat: TimeInterval = 30 * 60

    /// Share this Mac's local token and cost usage when it changed, then read
    /// every Mac's ledger for the usage source picker and combined totals.
    private func syncDeviceLedgers(force: Bool, removesEmptyLedger: Bool = false) async {
        guard !appConnectionRevoked else { return }
        let ledger = DeviceUsageMerge.ledger(
            deviceID: localDeviceID,
            deviceName: LocalDeviceIdentity.deviceName,
            details: providerDetails
        )
        let signature = Self.ledgerSignature(ledger)
        var shouldPublish = true
        if !force, let lastPublishedLedgerAt {
            let required = signature == lastPublishedLedgerSignature
                ? Self.ledgerPublishHeartbeat
                : Self.ledgerPublishSpacing
            shouldPublish = Date().timeIntervalSince(lastPublishedLedgerAt) >= required
        }

        if shouldPublish, !ledger.providers.isEmpty {
            do {
                try await usageSyncService.publishDeviceLedger(ledger)
                lastPublishedLedgerSignature = signature
                lastPublishedLedgerAt = Date()
            } catch {
                Logger.viewModel.error("Could not share this Mac's local usage: \(error.localizedDescription)")
            }
        } else if removesEmptyLedger, ledger.providers.isEmpty {
            // Every provider with local usage was turned off: withdraw this Mac's
            // earlier ledger so iPhone and iPad stop showing that usage.
            if await usageSyncService.deleteDeviceLedger(deviceID: localDeviceID) {
                lastPublishedLedgerSignature = nil
                lastPublishedLedgerAt = nil
            }
        }

        deviceLedgers = await usageSyncService.fetchDeviceLedgers()
    }

    /// Whole cents per provider for today and 30 days, effort session counts,
    /// plus the day and name.
    private static func ledgerSignature(_ ledger: DeviceUsageLedger) -> String {
        let providers = ledger.providers.map { entry in
            let today = Int((entry.today.costUSD * 100).rounded())
            let month = Int((entry.last30Days.costUSD * 100).rounded())
            let sessions = entry.effortSummaries.map { "\($0.period.rawValue)=\($0.totalSessionCount)" }
            return "\(entry.provider.rawValue):\(today):\(month):\(sessions.joined(separator: ","))"
        }
        return ([ledger.anchorDay, ledger.deviceName] + providers).joined(separator: "|")
    }

    /// The values a widget actually shows: whole-percent utilization and reset
    /// times per window. Fetch timestamps are excluded because they change on
    /// every refresh.
    private static func publishSignature(
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot]
    ) -> String {
        let providers = providerSnapshots
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
            .map { snapshot in
                let windows = snapshot.windows.map { window in
                    "\(window.windowID.rawValue)=\(Int(window.utilization.rounded()))@\(Int(window.resetsAt.timeIntervalSince1970 / 60))"
                }
                return "\(snapshot.provider.rawValue):\(snapshot.planName ?? ""):\(windows.joined(separator: ","))"
            }
        return ([planType] + providers).joined(separator: "|")
    }

    /// Builds the normal provider payload with local effort summaries attached.
    /// The payload remains the single Continuity Sync source for quota and local-usage metadata.
    private func continuityProviderSnapshots() -> [ProviderUsageSnapshot] {
        var snapshots = providerUsage
        let effortFetchedAt = tokenSnapshot?.fetchedAt ?? Date()

        if let snapshot, isProviderEnabled(.claude) {
            snapshots[.claude] = ProviderUsageSnapshot(
                claude: snapshot,
                planName: planType,
                effortSummaries: providerDetails[.claude]?.effortSummaries ?? [],
                lastUsedAt: providerDetails[.claude]?.lastUsedAt
            )
        }

        // Local-log usage can remain available when a provider's quota endpoint
        // is unavailable. Carry effort through the same provider payload even if
        // there are no rate-limit windows to attach it to.
        for (provider, detail) in providerDetails
        where snapshots[provider] == nil && !detail.effortSummaries.isEmpty && isProviderEnabled(provider) {
            snapshots[provider] = ProviderUsageSnapshot(
                provider: provider,
                windows: [],
                planName: provider == .claude ? planType : nil,
                effortSummaries: detail.effortSummaries,
                fetchedAt: effortFetchedAt,
                lastUsedAt: detail.lastUsedAt
            )
        }

        for (provider, providerSnapshot) in snapshots where provider != .claude {
            snapshots[provider] = ProviderUsageSnapshot(
                provider: providerSnapshot.provider,
                windows: providerSnapshot.windows,
                extraUsage: providerSnapshot.extraUsage,
                planName: providerSnapshot.planName,
                rateLimitResetCredits: providerSnapshot.rateLimitResetCredits,
                creditBalance: providerSnapshot.creditBalance,
                effortSummaries: providerDetails[provider]?.effortSummaries
                    ?? providerSnapshot.effortSummaries,
                // Providers whose quota endpoint returned no windows are refreshed
                // by the local log scan, so their freshness is the latest of the two
                // — without this the first-seen stamp would be carried forever.
                fetchedAt: providerSnapshot.windows.isEmpty
                    ? max(providerSnapshot.fetchedAt, effortFetchedAt)
                    : providerSnapshot.fetchedAt,
                lastUsedAt: providerDetails[provider]?.lastUsedAt
                    ?? providerSnapshot.lastUsedAt
            )
        }

        return enabledProviderSnapshots(from: snapshots.values)
    }
    #endif

    func revokeAppConnection() async {
        guard !isRevokingAppConnection else { return }
        isRevokingAppConnection = true
        defer { isRevokingAppConnection = false }

        appConnectionRevoked = true
        errorMessage = nil
        await notificationService.cancelResetNotifications()

        #if os(iOS)
        KeychainHelper.deleteCredentials()
        snapshotStore.clear()
        snapshot = nil
        planType = "Free"
        providerUsage.removeAll()
        isUsingCachedData = false
        isNoUsageData = false
        rateLimitedUntil.removeAll()
        activeIncidents.removeAll()
        receivedMacSyncedSnapshot = false
        deviceLedgers = []
        await WidgetDataManager.shared.clear()
        await liveActivityManager.stop()
        #endif

        #if os(macOS)
        _ = await usageSyncService.revokeAll()
        publishedSyncGeneration = nil
        continuityReceipts = [:]
        deviceLedgers = []
        lastPublishedLedgerSignature = nil
        lastPublishedLedgerAt = nil
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
    /// Refresh per-provider detail: Codex/Cursor/Grok rate-limit windows plus
    /// Claude/Codex/Grok token detail (today/yesterday/30-day, per-model, daily trend).
    private func refreshProviderUsage() async {
        for (provider, service) in providerUsageServices {
            // A provider turned off in Settings is never fetched.
            guard isProviderEnabled(provider) else { continue }
            // Like Claude, a provider in a rate-limit cooldown is skipped on every
            // refresh, manual included, and keeps its last snapshot meanwhile.
            if isCoolingDown(provider) { continue }
            do {
                let providerSnapshot = try await service.fetchSnapshot()
                // It may have been turned off while the request was in flight.
                guard isProviderEnabled(provider) else { continue }
                let oldProviderSnapshot = providerUsage[provider]
                providerUsage[provider] = providerSnapshot
                if let providerSnapshot {
                    await usageHistoryService.record(providerSnapshot: providerSnapshot)
                    await checkUsageNotifications(
                        oldSnapshot: oldProviderSnapshot,
                        newSnapshot: providerSnapshot
                    )
                }
                rateLimitedUntil[provider] = nil
                providerErrors[provider] = nil
                clearIncident(for: provider)
            } catch {
                guard isProviderEnabled(provider) else { continue }
                // Keep the provider's cached usage on every failure; its card shows
                // the error instead of disappearing. Signed-out services return nil
                // rather than throwing, so this never resurrects a removed account.
                providerErrors[provider] = error.localizedDescription
                if let cooldown = Self.rateLimitCooldown(for: error) {
                    rateLimitedUntil[provider] = Date().addingTimeInterval(cooldown)
                } else if Self.isOutageError(error) {
                    recordOutage(for: provider, error: error)
                }
            }
        }

        let refreshedDetails = await tokenUsageCoordinator.providerDetails(using: tokenSnapshot)
        providerDetails = addingUnavailableLocalUsageDetails(
            to: refreshedDetails.filter { isProviderEnabled($0.key) },
            from: enabledProviderSnapshots(from: providerUsage.values)
        )
    }

    /// Refresh token usage through the macOS persistence coordinator.
    private func refreshTokenUsage() async {
        // The token snapshot is Claude's local log usage; turned off, it is not read.
        guard isProviderEnabled(.claude) else {
            clearClaudeTokenUsage()
            return
        }
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
        // Claude may have been turned off while its logs were being read.
        if !isProviderEnabled(.claude) {
            clearClaudeTokenUsage()
        }
    }

    /// Drop Claude's local token usage so no stale totals or read errors remain.
    private func clearClaudeTokenUsage() {
        tokenSnapshot = nil
        periodSummaries = [:]
        selectedPeriodSummary = nil
        tokenUsageError = nil
    }

    /// Refresh the summary for the currently selected period (async, non-blocking)
    func refreshSelectedPeriodSummary() async {
        guard isProviderEnabled(.claude) else { return }
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
        await refresh()
        await armResetNotifications()
        startAutoRefresh()
    }

    func startAutoRefresh() {
        refreshScheduler.startAutoRefresh()
    }

    func stopAutoRefresh() {
        refreshScheduler.stopAutoRefresh()
    }
}
