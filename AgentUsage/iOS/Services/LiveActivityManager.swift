//
//  LiveActivityManager.swift
//  AgentUsage
//
//  Manages the single provider-neutral Live Activity lifecycle.
//

#if os(iOS)
import ActivityKit
import AgentUsageKit
import Combine
import Foundation
import OSLog

// MARK: - ActivityKit seam

/// The subset of ActivityKit lifecycle state that affects app-side ownership.
nonisolated enum LiveActivityLifecycleState: Sendable, Equatable {
    case active
    case stale
    case ended
    case dismissed
}

/// Type-erased access to one Agent Usage Live Activity.
///
/// Keeping ActivityKit behind this small seam makes lifecycle recovery and
/// ordering deterministic in tests without attempting to construct `Activity`.
@MainActor
protocol LiveActivityHandle: AnyObject {
    var id: String { get }
    var attributes: AgentUsageLiveActivityAttributes { get }
    var content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState> { get }
    var lifecycleState: LiveActivityLifecycleState { get }

    func update(_ content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>) async
    func endImmediately() async
    func stateUpdates() -> AsyncStream<LiveActivityLifecycleState>
}

@MainActor
protocol LiveActivityClient {
    var areActivitiesEnabled: Bool { get }
    var activities: [any LiveActivityHandle] { get }

    func request(
        attributes: AgentUsageLiveActivityAttributes,
        content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>
    ) throws -> any LiveActivityHandle
}

@MainActor
private final class SystemLiveActivityHandle: LiveActivityHandle {
    private let activity: Activity<AgentUsageLiveActivityAttributes>

    init(_ activity: Activity<AgentUsageLiveActivityAttributes>) {
        self.activity = activity
    }

    var id: String { activity.id }
    var attributes: AgentUsageLiveActivityAttributes { activity.attributes }
    var content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState> { activity.content }
    var lifecycleState: LiveActivityLifecycleState {
        Self.lifecycleState(from: activity.activityState)
    }

    func update(_ content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>) async {
        await activity.update(content)
    }

    func endImmediately() async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    func stateUpdates() -> AsyncStream<LiveActivityLifecycleState> {
        let updates = activity.activityStateUpdates
        return AsyncStream { continuation in
            let task = Task {
                for await state in updates {
                    continuation.yield(Self.lifecycleState(from: state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func lifecycleState(from state: ActivityState) -> LiveActivityLifecycleState {
        switch state {
        case .active:
            .active
        case .stale:
            .stale
        case .ended:
            .ended
        case .dismissed:
            .dismissed
        default:
            // New transitional ActivityKit states still represent a system-owned
            // activity. Keep tracking until an ended/dismissed state arrives.
            .active
        }
    }
}

@MainActor
private struct SystemLiveActivityClient: LiveActivityClient {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activities: [any LiveActivityHandle] {
        Activity<AgentUsageLiveActivityAttributes>.activities.map(SystemLiveActivityHandle.init)
    }

    func request(
        attributes: AgentUsageLiveActivityAttributes,
        content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>
    ) throws -> any LiveActivityHandle {
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        return SystemLiveActivityHandle(activity)
    }
}

// MARK: - Manager

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var isRunning = false
    @Published private(set) var activeSelection: UsageActivitySelection?
    @Published private(set) var activeWindowDisplayName: String?
    /// Set when activation fails so the control card can explain why it remained idle.
    @Published var startError: String?

    var activitiesEnabled: Bool { client.areActivitiesEnabled }

    private let client: any LiveActivityClient
    private let now: () -> Date
    private var currentActivity: (any LiveActivityHandle)?
    private var currentState: AgentUsageLiveActivityAttributes.ContentState?
    private var legacySelectedMetric: String?
    private var dismissedResetsAt: [UsageActivitySelection: TimeInterval] = [:]
    private var stateObservationTask: Task<Void, Never>?
    private var duplicateCleanupTask: Task<Void, Never>?

    init(
        client: (any LiveActivityClient)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client ?? SystemLiveActivityClient()
        self.now = now
        restoreExistingActivity()
    }

    deinit {
        stateObservationTask?.cancel()
        duplicateCleanupTask?.cancel()
    }

    // MARK: - Public lifecycle

    /// Starts tracking `selection`, or switches the existing activity in place.
    ///
    /// The exact provider/window pair is retained even if it is temporarily absent,
    /// allowing a subsequent sync to recover the activity without requesting another.
    func activate(
        selection: UsageActivitySelection,
        from snapshots: [ProviderUsageSnapshot]
    ) async {
        startError = nil
        dismissedResetsAt[selection] = nil

        guard client.areActivitiesEnabled else {
            Logger.liveActivity.warning("Live Activities not enabled")
            startError = "Live Activities are turned off. Enable them in Settings › \(Constants.appDisplayName)."
            return
        }

        await duplicateCleanupTask?.value
        duplicateCleanupTask = nil

        let protectsAcceptedTimestamp = activeSelection == selection
        guard let rendered = render(
            selection: selection,
            from: snapshots,
            protectingAcceptedTimestamp: protectsAcceptedTimestamp
        ) else {
            return
        }

        if let activity = currentActivity, activity.lifecycleState.isOwnedBySystem {
            legacySelectedMetric = nil
            accept(rendered, for: selection)
            await activity.update(rendered.content)
            Logger.liveActivity.info("Switched Live Activity in place: \(activity.id)")
            return
        }

        clearCurrentActivity(cancelObservation: true)
        let attributes = AgentUsageLiveActivityAttributes(
            selectedMetric: rendered.state.windowDisplayName ?? selection.windowID.rawValue
        )

        do {
            let activity = try client.request(attributes: attributes, content: rendered.content)
            currentActivity = activity
            legacySelectedMetric = nil
            accept(rendered, for: selection)
            observeState(of: activity)
            Logger.liveActivity.info("Started Live Activity: \(activity.id)")
        } catch let error as ActivityAuthorizationError {
            let reason = error.failureReason ?? String(describing: error)
            Logger.liveActivity.error("Failed to start (ActivityAuthorizationError): \(reason)")
            startError = reason
        } catch {
            Logger.liveActivity.error("Failed to start: \(error.localizedDescription)")
            startError = error.localizedDescription
        }
    }

    /// Updates the running activity and, when allowed, auto-starts a waiting-room
    /// Live Activity for the soonest short at-limit window.
    ///
    /// `canStart` must be false in the background: `Activity.request` is
    /// foreground-only. Updates to an already-running activity are still applied.
    func reconcile(
        from snapshots: [ProviderUsageSnapshot],
        autoPinAtLimit: Bool,
        canStart: Bool
    ) async {
        if currentActivity != nil {
            await refresh(from: snapshots)
        }

        guard autoPinAtLimit, client.areActivitiesEnabled else { return }
        guard let candidate = UsageWaitingRoom.nextLiveActivityCandidate(
            from: snapshots,
            now: now()
        ) else { return }

        if isDismissed(candidate) { return }

        if let active = activeSelection {
            if active == candidate.selection { return }
            if isEligibleWaitingRoom(active, in: snapshots),
               let activeReset = currentState?.resetsAt,
               activeReset <= candidate.window.resetsAt {
                return
            }
        }

        guard canStart else { return }
        await activate(selection: candidate.selection, from: snapshots)
    }

    /// Refreshes the active selection from all currently available provider data.
    func refresh(from snapshots: [ProviderUsageSnapshot]) async {
        guard let activity = currentActivity else { return }
        guard activity.lifecycleState.isOwnedBySystem else {
            clearCurrentActivity(cancelObservation: true)
            return
        }

        if let selection = activeSelection {
            guard let rendered = render(
                selection: selection,
                from: snapshots,
                protectingAcceptedTimestamp: true
            ) else {
                return
            }
            accept(rendered, for: selection)
            await activity.update(rendered.content)
            Logger.liveActivity.debug("Updated Live Activity")
            return
        }

        await refreshLegacyActivity(activity, from: snapshots)
    }

    func clearDismissals() {
        dismissedResetsAt.removeAll()
    }

    /// Immediately ends every Agent Usage activity, including recovered orphans.
    func stop() async {
        if let selection = activeSelection {
            let resetsAt = currentState?.resetsAt ?? now()
            dismissedResetsAt[selection] = floor(resetsAt.timeIntervalSince1970)
        }

        await duplicateCleanupTask?.value
        duplicateCleanupTask = nil

        stateObservationTask?.cancel()
        stateObservationTask = nil

        var activitiesByID: [String: any LiveActivityHandle] = [:]
        if let currentActivity {
            activitiesByID[currentActivity.id] = currentActivity
        }
        for activity in client.activities where activity.lifecycleState.isOwnedBySystem {
            activitiesByID[activity.id] = activitiesByID[activity.id] ?? activity
        }

        clearCurrentActivity(cancelObservation: false)
        startError = nil

        for activity in activitiesByID.values {
            await activity.endImmediately()
            Logger.liveActivity.info("Stopped Live Activity: \(activity.id)")
        }
    }

    // MARK: - Recovery

    private func restoreExistingActivity() {
        let activities = client.activities.filter { $0.lifecycleState.isOwnedBySystem }
        guard !activities.isEmpty else { return }

        let ordered = activities.sorted { lhs, rhs in
            let lhsDate = lhs.content.state.fetchedAt ?? .distantPast
            let rhsDate = rhs.content.state.fetchedAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.id > rhs.id
            }
            return lhsDate > rhsDate
        }
        guard let retained = ordered.first else { return }

        currentActivity = retained
        currentState = retained.content.state
        activeSelection = retained.content.state.selection
        activeWindowDisplayName = retained.content.state.windowDisplayName
            ?? retained.attributes.selectedMetric
        legacySelectedMetric = retained.content.state.selection == nil
            ? retained.attributes.selectedMetric
            : nil
        isRunning = true
        observeState(of: retained)
        Logger.liveActivity.debug("Restored Live Activity: \(retained.id)")

        let duplicates = Array(ordered.dropFirst())
        guard !duplicates.isEmpty else { return }
        duplicateCleanupTask = Task {
            for activity in duplicates {
                await activity.endImmediately()
                Logger.liveActivity.info("Ended duplicate Live Activity: \(activity.id)")
            }
        }
    }

    private func observeState(of activity: any LiveActivityHandle) {
        stateObservationTask?.cancel()
        let activityID = activity.id
        let updates = activity.stateUpdates()
        stateObservationTask = Task { [weak self] in
            for await state in updates {
                guard !Task.isCancelled, let self else { return }
                switch state {
                case .active, .stale:
                    if self.currentActivity?.id == activityID {
                        self.isRunning = true
                    }
                case .ended, .dismissed:
                    if self.currentActivity?.id == activityID {
                        if state == .dismissed {
                            self.recordDismissal()
                        }
                        self.clearCurrentActivity(cancelObservation: false)
                    }
                    return
                }
            }
        }
    }

    // MARK: - Rendering and ordering

    private struct RenderedContent {
        let state: AgentUsageLiveActivityAttributes.ContentState
        let content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>
    }

    private func render(
        selection: UsageActivitySelection,
        from snapshots: [ProviderUsageSnapshot],
        protectingAcceptedTimestamp: Bool
    ) -> RenderedContent? {
        let providerSnapshot = snapshots.first { $0.provider == selection.provider }
        let window = providerSnapshot?.windows.first { $0.windowID == selection.windowID }

        if protectingAcceptedTimestamp,
           let incomingDate = providerSnapshot?.fetchedAt,
           let acceptedDate = currentState?.fetchedAt,
           incomingDate < acceptedDate {
            Logger.liveActivity.debug("Ignored out-of-order Live Activity refresh")
            return nil
        }

        guard let providerSnapshot, let window else {
            let previousName = currentState?.selection == selection
                ? currentState?.windowDisplayName
                : nil
            let fetchedAt = providerSnapshot?.fetchedAt
                ?? (currentState?.selection == selection ? currentState?.fetchedAt : nil)
            let state = unavailableState(
                selection: selection,
                windowDisplayName: previousName ?? selection.windowID.rawValue,
                fetchedAt: fetchedAt
            )
            return RenderedContent(
                state: state,
                content: ActivityContent(state: state, staleDate: nil)
            )
        }

        let date = now()
        let isExpired = window.isExpired(from: date)
        let availability: UsageActivityAvailability = isExpired ? .awaitingRefresh : .available
        let state = AgentUsageLiveActivityAttributes.ContentState(
            percentUsed: isExpired ? 0 : window.percentUsed,
            timeUntilReset: isExpired ? "" : window.timeUntilReset(from: date),
            statusRaw: isExpired ? UsageStatus.onTrack.rawValue : window.status(from: date).rawValue,
            selection: selection,
            windowDisplayName: window.displayName,
            resetsAt: window.resetsAt,
            fetchedAt: providerSnapshot.fetchedAt,
            availabilityRaw: availability.rawValue
        )
        let freshnessDeadline = providerSnapshot.fetchedAt.addingTimeInterval(
            Constants.syncFallbackThreshold
        )
        let staleDate = min(window.resetsAt, freshnessDeadline)
        return RenderedContent(
            state: state,
            content: ActivityContent(state: state, staleDate: staleDate)
        )
    }

    private func refreshLegacyActivity(
        _ activity: any LiveActivityHandle,
        from snapshots: [ProviderUsageSnapshot]
    ) async {
        guard let selectedMetric = legacySelectedMetric else { return }
        let claudeSnapshot = snapshots.first { $0.provider == .claude }

        if let claudeSnapshot,
           let window = claudeSnapshot.windows.first(where: { $0.displayName == selectedMetric }) {
            let selection = UsageActivitySelection(provider: .claude, windowID: window.windowID)
            guard let rendered = render(
                selection: selection,
                from: snapshots,
                protectingAcceptedTimestamp: true
            ) else {
                return
            }
            legacySelectedMetric = nil
            accept(rendered, for: selection)
            await activity.update(rendered.content)
            Logger.liveActivity.info("Resolved legacy Live Activity to Claude \(window.windowID.rawValue)")
            return
        }

        if let incomingDate = claudeSnapshot?.fetchedAt,
           let acceptedDate = currentState?.fetchedAt,
           incomingDate < acceptedDate {
            return
        }
        let state = AgentUsageLiveActivityAttributes.ContentState(
            percentUsed: 0,
            timeUntilReset: "",
            statusRaw: UsageStatus.onTrack.rawValue,
            selection: nil,
            windowDisplayName: selectedMetric,
            resetsAt: nil,
            fetchedAt: claudeSnapshot?.fetchedAt ?? currentState?.fetchedAt,
            availabilityRaw: UsageActivityAvailability.unavailable.rawValue
        )
        let rendered = RenderedContent(
            state: state,
            content: ActivityContent(state: state, staleDate: nil)
        )
        accept(rendered, for: nil)
        await activity.update(rendered.content)
        Logger.liveActivity.debug("Legacy Live Activity selection is unavailable")
    }

    private func unavailableState(
        selection: UsageActivitySelection,
        windowDisplayName: String,
        fetchedAt: Date?
    ) -> AgentUsageLiveActivityAttributes.ContentState {
        AgentUsageLiveActivityAttributes.ContentState(
            percentUsed: 0,
            timeUntilReset: "",
            statusRaw: UsageStatus.onTrack.rawValue,
            selection: selection,
            windowDisplayName: windowDisplayName,
            resetsAt: nil,
            fetchedAt: fetchedAt,
            availabilityRaw: UsageActivityAvailability.unavailable.rawValue
        )
    }

    private func isDismissed(_ candidate: UsageWaitingRoom.Candidate) -> Bool {
        guard let dismissed = dismissedResetsAt[candidate.selection] else { return false }
        return dismissed == floor(candidate.window.resetsAt.timeIntervalSince1970)
    }

    private func isEligibleWaitingRoom(
        _ selection: UsageActivitySelection,
        in snapshots: [ProviderUsageSnapshot]
    ) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.provider == selection.provider }),
              let window = snapshot.windows.first(where: { $0.windowID == selection.windowID }) else {
            return false
        }
        return UsageWaitingRoom.isLiveActivityEligible(
            provider: selection.provider,
            window: window,
            now: now()
        )
    }

    private func recordDismissal() {
        guard let selection = activeSelection else { return }
        let resetsAt = currentState?.resetsAt ?? now()
        dismissedResetsAt[selection] = floor(resetsAt.timeIntervalSince1970)
    }

    private func accept(_ rendered: RenderedContent, for selection: UsageActivitySelection?) {
        // Commit ordering state before awaiting ActivityKit. A re-entrant older
        // refresh then observes the accepted timestamp and cannot win the race.
        currentState = rendered.state
        activeSelection = selection
        activeWindowDisplayName = rendered.state.windowDisplayName
        isRunning = true
    }

    private func clearCurrentActivity(cancelObservation: Bool) {
        if cancelObservation {
            stateObservationTask?.cancel()
            stateObservationTask = nil
        }
        currentActivity = nil
        currentState = nil
        legacySelectedMetric = nil
        activeSelection = nil
        activeWindowDisplayName = nil
        isRunning = false
    }
}

private extension LiveActivityLifecycleState {
    var isOwnedBySystem: Bool {
        switch self {
        case .active, .stale:
            true
        case .ended, .dismissed:
            false
        }
    }
}
#endif
