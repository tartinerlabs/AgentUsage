//
//  UsageViewModel.swift
//  ClaudeMeter
//

import Foundation
import ClaudeMeterKit
import SwiftUI
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
    private let minForceRefreshInterval: TimeInterval = 20
    private var hasInitialized = false

    /// Overall status computed from the worst status across all usage windows
    var overallStatus: UsageStatus {
        guard let snapshot else { return .onTrack }

        let statuses = [
            snapshot.session.status,
            snapshot.opus.status,
            snapshot.sonnet?.status
        ].compactMap { $0 }

        // Return worst status: critical > warning > onTrack
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning) { return .warning }
        return .onTrack
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
    }
    #else
    init(credentialProvider: any CredentialProvider) {
        self.credentialProvider = credentialProvider
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes
    }
    #endif

    func refresh(force: Bool = false) async {
        let minInterval = force ? minForceRefreshInterval : minRefreshInterval

        // Rate limit: skip if refreshed recently (first load always proceeds)
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minInterval {
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
            snapshot = try await apiService.fetchUsage(token: credentials.accessToken)

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
        }

        lastRefreshTime = Date()
        isLoading = false

        // Fetch token usage in background (macOS only)
        #if os(macOS)
        Task {
            await refreshTokenUsage()
        }
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
            print("Token usage error: \(error.localizedDescription)")
        } catch {
            tokenUsageError = .fileReadError(error)
            print("Token usage error: \(error)")
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
            print("Failed to fetch period summary: \(error)")
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
                        print("Failed to prefetch summary for \(period): \(error)")
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

enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual = "manual"
    case oneMinute = "1min"
    case twoMinutes = "2min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }
}

