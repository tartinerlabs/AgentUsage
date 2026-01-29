//
//  LiveActivityManager.swift
//  ClaudeMeter
//
//  Manages Live Activity lifecycle for usage tracking
//

#if os(iOS)
import ActivityKit
import ClaudeMeterKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var isRunning = false
    @Published var selectedMetric: MetricType = .session

    private var currentActivity: Activity<ClaudeMeterLiveActivityAttributes>?

    private init() {
        // Check for existing activities on init
        checkForExistingActivity()
    }

    // MARK: - Public Methods

    /// Start a new Live Activity with the given snapshot
    func start(snapshot: UsageSnapshot, metric: MetricType) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.liveActivity.warning("Live Activities not enabled")
            return
        }

        // End any existing activity first
        if currentActivity != nil {
            stop()
        }

        selectedMetric = metric
        let window = getWindow(from: snapshot, metric: metric)

        let attributes = ClaudeMeterLiveActivityAttributes(
            selectedMetric: metric.displayName
        )

        let contentState = ClaudeMeterLiveActivityAttributes.ContentState(from: window)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isRunning = true
            Logger.liveActivity.info("Started Live Activity: \(activity.id)")
        } catch {
            Logger.liveActivity.error("Failed to start: \(error.localizedDescription)")
        }
    }

    /// Update the current Live Activity with new data
    func update(snapshot: UsageSnapshot) {
        guard let activity = currentActivity else { return }

        let window = getWindow(from: snapshot, metric: selectedMetric)
        let contentState = ClaudeMeterLiveActivityAttributes.ContentState(from: window)

        Task {
            await activity.update(
                ActivityContent(state: contentState, staleDate: nil)
            )
            Logger.liveActivity.debug("Updated Live Activity")
        }
    }

    /// Stop the current Live Activity
    func stop() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            Logger.liveActivity.info("Stopped Live Activity")
        }

        currentActivity = nil
        isRunning = false
    }

    // MARK: - Private Methods

    private func checkForExistingActivity() {
        // Check if there's an existing activity from a previous session
        for activity in Activity<ClaudeMeterLiveActivityAttributes>.activities {
            currentActivity = activity
            isRunning = true
            Logger.liveActivity.debug("Found existing activity: \(activity.id)")
            break
        }
    }

    private func getWindow(from snapshot: UsageSnapshot, metric: MetricType) -> UsageWindow {
        switch metric {
        case .session:
            return snapshot.session
        case .opus:
            return snapshot.opus
        case .sonnet:
            return snapshot.sonnet ?? snapshot.opus
        }
    }
}
#endif
