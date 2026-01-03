//
//  UsageViewModel.swift
//  ClaudeMeter
//

import Foundation
import SwiftUI

@MainActor @Observable
final class UsageViewModel {
    var snapshot: UsageSnapshot?
    var tokenSnapshot: TokenUsageSnapshot?
    var planType: String = "Free"
    var isLoading = false
    var errorMessage: String?

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
        tokenService: TokenUsageService? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.tokenService = tokenService
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
        if let tokenService {
            Task {
                do {
                    tokenSnapshot = try await tokenService.fetchUsage()
                } catch {
                    print("Token usage error: \(error)")
                }
            }
        }
        #endif
    }

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
