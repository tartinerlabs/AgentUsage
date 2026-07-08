//
//  UsageViewModel.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit
import SwiftUI
import OSLog
#if os(macOS)
import SwiftData
#endif

@MainActor @Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot?
    var tokenSnapshot: TokenUsageSnapshot?
    var selectedPeriodSummary: TokenUsageSummary?
    #if os(macOS)
    var periodSummaries: [UsagePeriod: TokenUsageSummary] = [:]
    var isFetchingPeriodSummaries: Bool = false
    /// Codex rate-limit windows (5h / weekly) read from Codex CLI logs.
    var codexUsage: ProviderUsageSnapshot?
    /// OpenCode Go quota windows read from the authenticated dashboard page.
    var openCodeGoUsage: ProviderUsageSnapshot?
    /// Full per-provider detail (today/yesterday/30-day, per-model, daily trend)
    /// for all providers (Claude, Codex, OpenCode).
    var providerDetails: [Provider: ProviderDetail] = [:]
    #endif
    var planType: String = "Free"
    var isLoading = false
    var errorMessage: String?
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
        if let openCodeError = error as? OpenCodeGoUsageService.OpenCodeError {
            switch openCodeError {
            case .serverError(let code): return (500...599).contains(code) ? code : nil
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
        guard let lastUpdate = lastSuccessfulFetchTime else { return nil }
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

    private var lastSuccessfulFetchTime: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: cacheTimeKey)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: cacheTimeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: cacheTimeKey)
            }
        }
    }

    private let cacheKey = "cachedUsageSnapshot"
    private let cacheTimeKey = "cachedUsageSnapshotTime"
    /// Tracks the cost-model version that persisted history was last re-priced against.
    fileprivate static let costModelRepricedVersionKey = "costModelRepricedVersion"
    private let cachePlanKey = "cachedPlanType"
    /// Epoch-seconds timestamps gating once-per-day maintenance passes.
    private static let lastCleanupDateKey = "lastTokenCleanupDate"
    private static let lastZeroCostRecalcDateKey = "lastZeroCostRecalcDate"

    var refreshInterval: RefreshFrequency {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            restartAutoRefresh()
        }
    }

    var showExtraUsageIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showExtraUsageIndicators, forKey: "showExtraUsageIndicators")
        }
    }

    #if os(macOS)
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled {
                Task { await NotificationService.shared.requestPermission() }
            }
        }
    }

    var menuBarShowSession: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowSession, forKey: "menuBarShowSession")
        }
    }

    var menuBarShowAllModels: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowAllModels, forKey: "menuBarShowAllModels")
        }
    }

    var menuBarShowSonnet: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowSonnet, forKey: "menuBarShowSonnet")
        }
    }

    var menuBarShowDesign: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowDesign, forKey: "menuBarShowDesign")
        }
    }

    var menuBarShowFable: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowFable, forKey: "menuBarShowFable")
        }
    }

    var menuBarShowCodex: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowCodex, forKey: "menuBarShowCodex")
        }
    }

    var menuBarShowExtraUsage: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowExtraUsage, forKey: "menuBarShowExtraUsage")
        }
    }

    #if DEBUG
    var debugSimulate100Percent: Bool = false
    #endif
    #endif

    private let credentialProvider: any CredentialProvider
    private let apiService: any APIServiceProtocol
    private let usageHistoryService: UsageHistoryService
    #if os(macOS)
    private let tokenService: TokenUsageService?
    private let tokenRepository: TokenUsageRepository?
    private let tokenQuerier: TokenUsageQuerier?
    private let blogUsageSyncService: BlogUsageSyncService?
    private let blogOAuthService: BlogOAuthService?
    private let codexUsageService: CodexUsageService?
    private let openCodeGoUsageService: OpenCodeGoUsageService?
    #endif
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 30
    private var hasInitialized = false

    /// Overall status computed from the worst status across all usage windows
    var overallStatus: UsageStatus {
        UsageCalculations.overallStatus(from: snapshot)
    }

    #if os(macOS)
    init(
        credentialProvider: any CredentialProvider,
        apiService: (any APIServiceProtocol)? = nil,
        tokenService: TokenUsageService? = nil,
        blogUsageSyncService: BlogUsageSyncService? = nil,
        blogOAuthService: BlogOAuthService? = nil,
        codexUsageService: CodexUsageService? = nil,
        openCodeGoUsageService: OpenCodeGoUsageService? = nil,
        usageHistoryService: UsageHistoryService? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.apiService = apiService ?? ClaudeAPIService()
        self.tokenService = tokenService
        self.tokenRepository = modelContext.map { TokenUsageRepository(modelContext: $0) }
        self.tokenQuerier = modelContext.map { TokenUsageQuerier(modelContainer: $0.container) }
        self.usageHistoryService = usageHistoryService
            ?? modelContext.map { UsageHistoryService(repository: UsageHistoryRepository(modelContainer: $0.container)) }
            ?? UsageHistoryService.shared
        self.blogUsageSyncService = blogUsageSyncService
        self.blogOAuthService = blogOAuthService
        self.codexUsageService = codexUsageService
        self.openCodeGoUsageService = openCodeGoUsageService
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes
        self.showExtraUsageIndicators = UserDefaults.standard.object(forKey: "showExtraUsageIndicators") as? Bool ?? true
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        self.blogUsageSyncEnabled = UserDefaults.standard.object(forKey: "blogUsageSyncEnabled") as? Bool ?? false
        self.blogUsageSyncEndpointURLString = UserDefaults.standard.string(forKey: "blogUsageSyncEndpointURL") ?? BlogUsageSyncService.defaultEndpointURLString

        // Menu bar display settings - default to showing session only
        let defaults = UserDefaults.standard
        self.menuBarShowSession = defaults.object(forKey: "menuBarShowSession") as? Bool ?? true
        self.menuBarShowAllModels = defaults.object(forKey: "menuBarShowAllModels") as? Bool ?? false
        self.menuBarShowSonnet = defaults.object(forKey: "menuBarShowSonnet") as? Bool ?? false
        self.menuBarShowDesign = defaults.object(forKey: "menuBarShowDesign") as? Bool ?? false
        self.menuBarShowFable = defaults.object(forKey: "menuBarShowFable") as? Bool ?? false
        self.menuBarShowCodex = defaults.object(forKey: "menuBarShowCodex") as? Bool ?? false
        self.menuBarShowExtraUsage = defaults.object(forKey: "menuBarShowExtraUsage") as? Bool ?? true

        // Load cached data on init
        loadCachedSnapshot()
    }
    #else
    init(credentialProvider: any CredentialProvider, apiService: (any APIServiceProtocol)? = nil) {
        self.credentialProvider = credentialProvider
        self.apiService = apiService ?? ClaudeAPIService()
        self.usageHistoryService = UsageHistoryService.shared
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes
        self.showExtraUsageIndicators = UserDefaults.standard.object(forKey: "showExtraUsageIndicators") as? Bool ?? true

        // Load cached data on init
        loadCachedSnapshot()
    }
    #endif

    // MARK: - Cache Management

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return
        }
        snapshot = cached
        planType = UserDefaults.standard.string(forKey: cachePlanKey) ?? "Free"
        isUsingCachedData = true
        Logger.viewModel.debug("Loaded cached snapshot from \(self.timeSinceLastUpdate ?? "unknown time")")
    }

    private func cacheSnapshot(_ snapshot: UsageSnapshot, planType: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(planType, forKey: cachePlanKey)
        lastSuccessfulFetchTime = Date()
        Logger.viewModel.debug("Cached snapshot successfully")
    }

    func refresh(force: Bool = false) async {
        // Rate limit auto-refresh; a forced refresh (manual) always proceeds.
        if !force,
           let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minRefreshInterval {
            return
        }
        // Gate the batch on when it last RAN, not on Claude's success. This keeps the
        // debounce while ensuring Claude's outcome never decides whether the other
        // providers may refresh.
        lastRefreshTime = Date()

        // Fetch each provider concurrently and independently so a slow, retrying, or
        // failing Claude fetch can never delay or block Codex/OpenCode. iOS is Claude-only.
        #if os(macOS)
        async let claudeArm: Void = refreshClaude()
        // Extra providers share one arm because refreshProviderUsage() reads the
        // tokenSnapshot produced by refreshTokenUsage(); the Codex/OpenCode API fetches
        // inside it are already independent of the Claude API.
        async let providersArm: Void = refreshExtraProviders()
        _ = await (claudeArm, providersArm)
        Task { await runPassiveBlogUsageSync() }
        #else
        await refreshClaude()
        #endif
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
    private func refreshClaude() async {
        // API usage fetch (requires network)
        if isOffline {
            if snapshot != nil {
                Logger.viewModel.info("Offline - using cached data")
                isUsingCachedData = true
                errorMessage = nil  // Clear error since we have cached data
            } else {
                errorMessage = "No internet connection and no cached data available."
            }
            return
        }

        isLoading = true
        errorMessage = nil
        isNoUsageData = false  // Reset on each online fetch attempt

        // Store old snapshot for threshold comparison (macOS only)
        #if os(macOS)
        let oldSnapshot = snapshot
        #endif

        do {
            let credentials = try await credentialProvider.loadCredentials()
            planType = credentials.planDisplayName
            let newSnapshot = try await apiService.fetchUsage(token: credentials.accessToken)
            snapshot = newSnapshot
            isUsingCachedData = false
            isNoUsageData = false
            clearIncident(for: .claude)  // Successful fetch ends any active outage

            // Cache the successful response
            cacheSnapshot(newSnapshot, planType: planType)

            // Record to usage history for trend tracking
            await usageHistoryService.record(snapshot: newSnapshot)

            // Check for threshold crossings and send notifications (macOS only)
            #if os(macOS)
            if notificationsEnabled, let newSnapshot = snapshot {
                await NotificationService.shared.checkThresholdCrossings(
                    oldSnapshot: oldSnapshot,
                    newSnapshot: newSnapshot
                )
            }
            #endif

            // Cache snapshot for widgets and update Live Activity (iOS only)
            #if os(iOS)
            if let snapshot {
                await WidgetDataManager.shared.save(snapshot)
                await LiveActivityManager.shared.update(snapshot: snapshot)
            }
            #endif
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
                isLoading = false
                return
            }

            errorMessage = error.localizedDescription
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
        }

        isLoading = false
    }

    #if os(macOS)
    /// Refresh per-provider detail: Codex rate-limit windows + Claude/Codex/OpenCode
    /// token detail (today/yesterday/30-day, per-model, daily trend).
    private func refreshProviderUsage() async {
        if let codexUsageService {
            do {
                codexUsage = try await codexUsageService.fetchSnapshot()
                clearIncident(for: .codex)
            } catch {
                if Self.isOutageError(error) {
                    recordOutage(for: .codex, error: error)  // keep cached codexUsage
                } else {
                    codexUsage = nil  // preserve existing hide-on-error behavior
                }
            }
        }
        if let openCodeGoUsageService {
            do {
                openCodeGoUsage = try await openCodeGoUsageService.fetchSnapshot()
                clearIncident(for: .openCode)
            } catch {
                if Self.isOutageError(error) {
                    recordOutage(for: .openCode, error: error)  // keep cached openCodeGoUsage
                } else {
                    openCodeGoUsage = nil  // preserve existing hide-on-error behavior
                }
            }
        }

        var details: [Provider: ProviderDetail] = [:]

        // Codex + OpenCode from local-log sources
        if let tokenService {
            let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            details = await tokenService.fetchExtraProviderDetails(since: since)
        }

        // Claude from the SwiftData path + live snapshot
        if let snapshot = tokenSnapshot {
            var points: [DailyTokenPoint] = []
            if let querier = tokenQuerier {
                points = (try? await querier.fetchDailyTokenPoints(days: 30)) ?? []
            }
            let yesterdayPoint = points.count >= 2 ? points[points.count - 2] : nil
            details[.claude] = ProviderDetail(
                today: snapshot.today,
                yesterday: TokenUsageSummary(
                    tokens: TokenCount(inputTokens: yesterdayPoint?.tokens ?? 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0),
                    costUSD: yesterdayPoint?.costUSD ?? 0,
                    period: .today
                ),
                last30Days: snapshot.last30Days,
                byModel: snapshot.byModel,
                dailyCosts: points.map(\.costUSD)
            )
        }

        providerDetails = details
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

    /// True if ≥24h have elapsed since the epoch-seconds timestamp stored at `key`
    /// (or it was never set). Does not update the stored value.
    private static func shouldRunMaintenance(key: String) -> Bool {
        let last = UserDefaults.standard.double(forKey: key)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= 24 * 60 * 60
    }

    /// Refresh token usage from SwiftData repository (with incremental import)
    private func refreshTokenUsage() async {
        isLoadingTokenUsage = true
        tokenUsageError = nil

        defer { isLoadingTokenUsage = false }

        do {
            // If repository available, import new entries and query from SwiftData
            if let repository = tokenRepository, let service = tokenService {
                // Get current file states for incremental reading
                let fileStates: [String: TokenUsageService.FileState]
                do {
                    fileStates = try repository.getAllFileStates()
                } catch {
                    throw TokenUsageError.swiftDataError(error)
                }

                // Get parsed entries from service (incremental - only new content)
                let parsedResults: [URL: TokenUsageService.IncrementalParseResult]
                do {
                    parsedResults = try await service.fetchParsedEntries(fileStates: fileStates)
                } catch {
                    throw TokenUsageError.fileReadError(error)
                }

                // Import new entries and update file states
                for (fileURL, result) in parsedResults {
                    do {
                        try await repository.importEntries(
                            result.entries,
                            forFile: fileURL,
                            newByteOffset: result.newByteOffset,
                            newFileSize: result.newFileSize,
                            newModified: result.newModified
                        )
                    } catch {
                        throw TokenUsageError.swiftDataError(error)
                    }
                }

                // Trim entries past the 13-month retention window at most once per day.
                // This is a menu-bar app that can run for weeks, so gate on elapsed
                // time, not launch count.
                if Self.shouldRunMaintenance(key: Self.lastCleanupDateKey) {
                    try? await repository.cleanupOldEntries()
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCleanupDateKey)
                }

                // Reprice $0 rows only when the LiteLLM pricing cache may have changed
                // (~24h TTL), instead of a full-table scan on every refresh.
                if Self.shouldRunMaintenance(key: Self.lastZeroCostRecalcDateKey) {
                    _ = try? await repository.recalculateZeroCostEntries()
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastZeroCostRecalcDateKey)
                }

                // One-time re-price of all persisted history after a cost-model change.
                // Runs once per cost-model version. v3 reverts the 200k tiered
                // pricing that was wrongly applied to daily aggregates (aeea0f7),
                // re-pricing any rows imported during that window at the flat rate.
                let costModelVersion = 3
                if UserDefaults.standard.integer(forKey: Self.costModelRepricedVersionKey) < costModelVersion {
                    _ = try? await repository.recalculateAllCosts()
                    UserDefaults.standard.set(costModelVersion, forKey: Self.costModelRepricedVersionKey)
                }

                // Query snapshot via background actor (prefer querier to avoid main-actor hops)
                do {
                    if let querier = tokenQuerier {
                        tokenSnapshot = try await querier.fetchSnapshot()
                    } else {
                        tokenSnapshot = try await repository.fetchSnapshot()
                    }
                } catch {
                    throw TokenUsageError.swiftDataError(error)
                }

                // Seed the two periods fetchSnapshot already computed; fetch only the
                // visible period if it isn't one of them. Longer periods (90/180/365d)
                // load on demand via DashboardTabView's .task(id: selectedTokenPeriod).
                periodSummaries[.today] = tokenSnapshot?.today
                periodSummaries[.last30Days] = tokenSnapshot?.last30Days
                if selectedTokenPeriod != .today && selectedTokenPeriod != .last30Days {
                    await refreshSelectedPeriodSummary()
                } else {
                    selectedPeriodSummary = periodSummaries[selectedTokenPeriod]
                }

            } else if let service = tokenService {
                // Fallback to direct service query (no persistence)
                do {
                    tokenSnapshot = try await service.fetchUsage()
                } catch {
                    throw TokenUsageError.fileReadError(error)
                }
            } else {
                throw TokenUsageError.repositoryUnavailable
            }

            // Success - clear any previous error
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
            if let querier = tokenQuerier {
                let summary = try await querier.fetchSummary(for: selectedTokenPeriod)
                periodSummaries[selectedTokenPeriod] = summary
                selectedPeriodSummary = summary
            } else if let repository = tokenRepository {
                let summary = try await repository.fetchSummary(for: selectedTokenPeriod)
                periodSummaries[selectedTokenPeriod] = summary
                selectedPeriodSummary = summary
            }
        } catch {
            // Set error but don't override existing tokenSnapshot
            if tokenUsageError == nil {
                tokenUsageError = .swiftDataError(error)
            }
            Logger.tokenUsage.error("Failed to fetch period summary: \(error)")
        }
    }

    /// Prefetch and cache summaries for all periods to make Picker selection instant
    private func prefetchAllPeriodSummaries() async {
        let querier = tokenQuerier
        let repository = tokenRepository
        if querier == nil && repository == nil { return }
        isFetchingPeriodSummaries = true
        defer { isFetchingPeriodSummaries = false }

        // Fetch all periods in parallel
        let periods = UsagePeriod.allCases
        // Build a dictionary by fetching each period concurrently
        var results: [UsagePeriod: TokenUsageSummary] = [:]

        await withTaskGroup(of: (UsagePeriod, TokenUsageSummary)?.self) { group in
            for period in periods {
                group.addTask {
                    do {
                        if let querier {
                            let summary = try await querier.fetchSummary(for: period)
                            return (period, summary)
                        } else if let repository {
                            let summary = try await repository.fetchSummary(for: period)
                            return (period, summary)
                        } else {
                            return nil
                        }
                    } catch {
                        Logger.tokenUsage.error("Failed to prefetch summary for \(period.rawValue): \(error)")
                        return nil
                    }
                }
            }

            for await pair in group {
                if let (period, summary) = pair {
                    results[period] = summary
                }
            }
        }

        // Update cache on main actor (we're @MainActor already)
        periodSummaries = results
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
        restartAutoRefresh()
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func restartAutoRefresh() {
        refreshTask?.cancel()

        guard let interval = refreshInterval.timeInterval else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await refresh()
                }
            }
        }
    }
}

// Note: RefreshFrequency enum is now in Shared/ViewModels/RefreshScheduler.swift
// Note: MenuBarDisplayWindow enum is now in macOS/ViewModels/MenuBarSettingsManager.swift
