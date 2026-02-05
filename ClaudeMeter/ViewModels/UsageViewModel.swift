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
    #endif
    var planType: String = "Free"
    var isLoading = false
    var errorMessage: String?
    #if os(macOS)
    var tokenUsageError: TokenUsageError?
    var isLoadingTokenUsage = false
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
    private let cachePlanKey = "cachedPlanType"

    var refreshInterval: RefreshFrequency {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            restartAutoRefresh()
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

    #if DEBUG
    var debugSimulate100Percent: Bool = false
    #endif
    #endif

    private let credentialProvider: any CredentialProvider
    private let apiService = ClaudeAPIService()
    #if os(macOS)
    private let tokenService: TokenUsageService?
    private let tokenRepository: TokenUsageRepository?
    private let tokenQuerier: TokenUsageQuerier?
    #endif
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 30
    private let minForceRefreshInterval: TimeInterval = 5  // Reduced from 20s for better UX
    private var hasInitialized = false

    /// Overall status computed from the worst status across all usage windows
    var overallStatus: UsageStatus {
        UsageCalculations.overallStatus(from: snapshot)
    }

    #if os(macOS)
    init(
        credentialProvider: any CredentialProvider,
        tokenService: TokenUsageService? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.tokenService = tokenService
        self.tokenRepository = modelContext.map { TokenUsageRepository(modelContext: $0) }
        self.tokenQuerier = modelContext.map { TokenUsageQuerier(modelContainer: $0.container) }
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")

        // Menu bar display settings - default to showing session only
        let defaults = UserDefaults.standard
        self.menuBarShowSession = defaults.object(forKey: "menuBarShowSession") as? Bool ?? true
        self.menuBarShowAllModels = defaults.object(forKey: "menuBarShowAllModels") as? Bool ?? false
        self.menuBarShowSonnet = defaults.object(forKey: "menuBarShowSonnet") as? Bool ?? false

        // Load cached data on init
        loadCachedSnapshot()
    }
    #else
    init(credentialProvider: any CredentialProvider) {
        self.credentialProvider = credentialProvider
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes

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
        let minInterval = force ? minForceRefreshInterval : minRefreshInterval

        // Rate limit: skip if refreshed recently (first load always proceeds)
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minInterval {
            return
        }

        // Check network status - use cached data if offline
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

        // Store old snapshot for threshold comparison (macOS only)
        #if os(macOS)
        let oldSnapshot = snapshot
        #endif

        do {
            let credentials = try await credentialProvider.loadCredentials()
            planType = credentials.planDisplayName
            let newSnapshot = try await apiService.fetchUsage(token: credentials.accessToken)
            snapshot = newSnapshot
            lastRefreshTime = Date()  // Only set on success - allows immediate retry on failure
            isUsingCachedData = false

            // Cache the successful response
            cacheSnapshot(newSnapshot, planType: planType)

            // Record to usage history for trend tracking
            await UsageHistoryService.shared.record(snapshot: newSnapshot)

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
            errorMessage = error.localizedDescription
            // If we have cached data, use it and show a softer error
            if snapshot != nil {
                isUsingCachedData = true
                Logger.viewModel.warning("API fetch failed, using cached data: \(error.localizedDescription)")
            }
            // Don't set lastRefreshTime on error - allow immediate retry
        }

        isLoading = false

        // Fetch token usage in background (macOS only)
        // Use async let to ensure task is properly structured and awaited
        #if os(macOS)
        await refreshTokenUsage()
        #endif
    }

    #if os(macOS)
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

                // Prefetch and cache summaries for all periods
                await prefetchAllPeriodSummaries()
                // Update the currently selected period summary from cache
                selectedPeriodSummary = periodSummaries[selectedTokenPeriod]

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
