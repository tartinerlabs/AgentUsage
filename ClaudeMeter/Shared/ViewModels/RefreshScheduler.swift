//
//  RefreshScheduler.swift
//  ClaudeMeter
//
//  Manages auto-refresh scheduling for usage data
//

import Foundation

/// Manages auto-refresh scheduling for periodic data fetching
@MainActor @Observable
final class RefreshScheduler {
    /// Current refresh interval setting
    var refreshInterval: RefreshFrequency {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            restartAutoRefresh()
        }
    }

    /// Callback to execute on each refresh
    var onRefresh: (() async -> Void)?

    private var refreshTask: Task<Void, Never>?

    init() {
        let savedInterval = UserDefaults.standard.string(forKey: "refreshInterval")
        self.refreshInterval = RefreshFrequency(rawValue: savedInterval ?? "") ?? .fiveMinutes
    }

    /// Start the auto-refresh schedule
    func startAutoRefresh() {
        restartAutoRefresh()
    }

    /// Stop the auto-refresh schedule
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Restart the auto-refresh schedule with current interval
    func restartAutoRefresh() {
        refreshTask?.cancel()

        guard let interval = refreshInterval.timeInterval else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await onRefresh?()
                }
            }
        }
    }
}

/// Refresh frequency options
enum RefreshFrequency: String, CaseIterable, Identifiable, Sendable {
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
