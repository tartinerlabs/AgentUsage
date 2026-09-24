//
//  RefreshScheduler.swift
//  AgentUsage
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
            defaults.set(refreshInterval.rawValue, forKey: Self.refreshIntervalKey)
            restartAutoRefresh()
        }
    }

    /// Callback to execute on each refresh
    var onRefresh: (() async -> Void)?

    /// When the running schedule fires next. `nil` while no schedule is running
    /// (Manual, or stopped) and while a scheduled refresh is in flight.
    private(set) var nextScheduledRefresh: Date?

    private static let refreshIntervalKey = "refreshInterval"
    private let defaults: UserDefaults
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let savedInterval = defaults.string(forKey: Self.refreshIntervalKey)
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
        nextScheduledRefresh = nil
    }

    /// Restart the auto-refresh schedule with current interval
    private func restartAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil

        guard let interval = refreshInterval.timeInterval else {
            nextScheduledRefresh = nil
            return
        }

        nextScheduledRefresh = now().addingTimeInterval(interval)
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                // A cancelled loop must not write: a newer schedule owns the date.
                guard !Task.isCancelled else { return }
                nextScheduledRefresh = nil
                await onRefresh?()
                guard !Task.isCancelled else { return }
                // The next sleep starts once the refresh finishes.
                nextScheduledRefresh = now().addingTimeInterval(interval)
            }
        }
    }
}

/// Refresh frequency options
enum RefreshFrequency: String, CaseIterable, Identifiable, Sendable {
    case adaptive = "adaptive"
    case manual = "manual"
    case oneMinute = "1min"
    case twoMinutes = "2min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptive: return "Adaptive"
        case .manual: return "Manual"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .adaptive:
            #if os(macOS)
            return ProcessInfo.processInfo.isLowPowerModeEnabled ? 900 : 300
            #else
            return 300
            #endif
        case .manual: return nil
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }
}
