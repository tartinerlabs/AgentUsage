#if os(iOS)
import ActivityKit
import AgentUsageKit
import Foundation
import Testing
@testable import AgentUsage

@Suite("LiveActivityManager", .serialized)
@MainActor
struct LiveActivityManagerTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func legacyContentStateJSONDecodesWithProviderFieldsAbsent() throws {
        let json = Data(
            #"{"percentUsed":42,"timeUntilReset":"1h 5m","statusRaw":"warning"}"#.utf8
        )

        let state = try JSONDecoder().decode(
            AgentUsageLiveActivityAttributes.ContentState.self,
            from: json
        )

        #expect(state.percentUsed == 42)
        #expect(state.timeUntilReset == "1h 5m")
        #expect(state.status == .warning)
        #expect(state.selection == nil)
        #expect(state.windowDisplayName == nil)
        #expect(state.resetsAt == nil)
        #expect(state.fetchedAt == nil)
        #expect(state.availability == .available)
    }

    @Test func providerSelectionsRoundTripIncludingCursorCustomWindow() throws {
        let selections = [
            UsageActivitySelection(provider: .claude, windowID: "session"),
            UsageActivitySelection(provider: .codex, windowID: "codex-weekly"),
            UsageActivitySelection(provider: .cursor, windowID: "cursor.dynamic.usage-2026"),
        ]

        let encoded = try JSONEncoder().encode(selections)
        let decoded = try JSONDecoder().decode([UsageActivitySelection].self, from: encoded)

        #expect(decoded == selections)
        #expect(decoded.last?.windowID.rawValue == "cursor.dynamic.usage-2026")
    }

    @Test func startsExactProviderWindowWithFreshnessDeadline() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .codex, windowID: "codex-weekly")
        let fetchedAt = referenceDate.addingTimeInterval(-21_000)
        let snapshot = makeSnapshot(
            provider: .codex,
            windowID: selection.windowID,
            name: "Weekly limit",
            utilization: 42,
            resetsAt: referenceDate.addingTimeInterval(3_600),
            fetchedAt: fetchedAt
        )

        await manager.activate(selection: selection, from: [snapshot])

        #expect(client.requestCount == 1)
        #expect(manager.isRunning)
        #expect(manager.activeSelection == selection)
        #expect(manager.activeWindowDisplayName == "Weekly limit")
        let activity = try #require(client.requestedActivities.first)
        #expect(activity.content.state.selection == selection)
        #expect(activity.content.state.percentUsed == 42)
        #expect(activity.content.state.availability == .available)
        #expect(
            activity.content.staleDate
                == fetchedAt.addingTimeInterval(Constants.syncFallbackThreshold)
        )
    }

    @Test func disabledAuthorizationAndRequestFailureRemainIdle() async {
        let disabledClient = FakeLiveActivityClient()
        disabledClient.areActivitiesEnabled = false
        let disabledManager = LiveActivityManager(client: disabledClient, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .claude, windowID: "session")

        await disabledManager.activate(
            selection: selection,
            from: [makeSnapshot(provider: .claude, windowID: "session")]
        )

        #expect(!disabledManager.isRunning)
        #expect(disabledManager.startError?.contains("Settings") == true)
        #expect(disabledClient.requestCount == 0)

        let failingClient = FakeLiveActivityClient()
        failingClient.requestError = FakeActivityError.requestFailed
        let failingManager = LiveActivityManager(client: failingClient, now: { referenceDate })
        await failingManager.activate(
            selection: selection,
            from: [makeSnapshot(provider: .claude, windowID: "session")]
        )

        #expect(!failingManager.isRunning)
        #expect(failingManager.startError == "Test request failed")
        #expect(failingClient.requestCount == 1)
    }

    @Test func switchesProvidersByUpdatingTheExistingActivity() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let claude = UsageActivitySelection(provider: .claude, windowID: "session")
        let codex = UsageActivitySelection(provider: .codex, windowID: "codex-weekly")
        let cursor = UsageActivitySelection(provider: .cursor, windowID: "cursor.total")
        let snapshots = [
            makeSnapshot(provider: .claude, windowID: claude.windowID),
            makeSnapshot(provider: .codex, windowID: codex.windowID),
            makeSnapshot(provider: .cursor, windowID: cursor.windowID),
        ]

        await manager.activate(selection: claude, from: snapshots)
        let activity = try #require(client.requestedActivities.first)
        let originalID = activity.id
        await manager.activate(selection: codex, from: snapshots)
        await manager.activate(selection: cursor, from: snapshots)

        #expect(client.requestCount == 1)
        #expect(activity.id == originalID)
        #expect(activity.updates.count == 2)
        #expect(activity.content.state.selection == cursor)
        #expect(manager.activeSelection == cursor)
        #expect(activity.endCount == 0)
    }

    @Test func olderRefreshCannotOverwriteAcceptedContent() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .cursor, windowID: "cursor.total")

        await manager.activate(
            selection: selection,
            from: [makeSnapshot(
                provider: .cursor,
                windowID: selection.windowID,
                utilization: 30,
                fetchedAt: referenceDate
            )]
        )
        let activity = try #require(client.requestedActivities.first)
        await manager.refresh(from: [makeSnapshot(
            provider: .cursor,
            windowID: selection.windowID,
            utilization: 80,
            fetchedAt: referenceDate.addingTimeInterval(60)
        )])
        await manager.refresh(from: [makeSnapshot(
            provider: .cursor,
            windowID: selection.windowID,
            utilization: 10,
            fetchedAt: referenceDate.addingTimeInterval(30)
        )])

        #expect(activity.updates.count == 1)
        #expect(activity.content.state.percentUsed == 80)
        #expect(activity.content.state.fetchedAt == referenceDate.addingTimeInterval(60))
    }

    @Test func missingWindowBecomesUnavailableAndLaterRecovers() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .cursor, windowID: "cursor.custom")
        await manager.activate(
            selection: selection,
            from: [makeSnapshot(provider: .cursor, windowID: selection.windowID)]
        )
        let activity = try #require(client.requestedActivities.first)

        // A provider-only activity must still be refreshed when the latest sync
        // omits that provider entirely; the stable selection is retained.
        await manager.refresh(from: [])

        #expect(activity.content.state.selection == selection)
        #expect(activity.content.state.availability == .unavailable)
        #expect(activity.content.state.fetchedAt == referenceDate)

        await manager.refresh(from: [makeSnapshot(
            provider: .cursor,
            windowID: "cursor.other",
            fetchedAt: referenceDate.addingTimeInterval(60)
        )])

        #expect(activity.content.state.selection == selection)
        #expect(activity.content.state.availability == .unavailable)
        #expect(activity.content.state.percentUsed == 0)
        #expect(activity.content.state.resetsAt == nil)

        await manager.refresh(from: [makeSnapshot(
            provider: .cursor,
            windowID: selection.windowID,
            name: "Custom window",
            utilization: 67,
            fetchedAt: referenceDate.addingTimeInterval(120)
        )])

        #expect(activity.content.state.availability == .available)
        #expect(activity.content.state.percentUsed == 67)
        #expect(activity.content.state.windowDisplayName == "Custom window")
        #expect(client.requestCount == 1)
    }

    @Test func expiredWindowAwaitsRefreshWithoutOldPercentage() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .codex, windowID: "codex-weekly")

        await manager.activate(
            selection: selection,
            from: [makeSnapshot(
                provider: .codex,
                windowID: selection.windowID,
                utilization: 95,
                resetsAt: referenceDate.addingTimeInterval(-1)
            )]
        )

        let activity = try #require(client.requestedActivities.first)
        #expect(activity.content.state.availability == .awaitingRefresh)
        #expect(activity.content.state.percentUsed == 0)
        #expect(activity.content.state.timeUntilReset.isEmpty)
        #expect(activity.content.staleDate == referenceDate.addingTimeInterval(-1))
    }

    @Test func legacyClaudeMetricRequiresAnExactDisplayNameMatch() async throws {
        let legacyState = AgentUsageLiveActivityAttributes.ContentState(
            percentUsed: 70,
            timeUntilReset: "1h",
            statusRaw: UsageStatus.warning.rawValue
        )
        let legacyActivity = FakeLiveActivityHandle(
            id: "legacy",
            attributes: AgentUsageLiveActivityAttributes(selectedMetric: "Sonnet"),
            content: ActivityContent(state: legacyState, staleDate: nil)
        )
        let client = FakeLiveActivityClient(activities: [legacyActivity])
        let manager = LiveActivityManager(client: client, now: { referenceDate })

        await manager.refresh(from: [makeSnapshot(
            provider: .claude,
            windowID: "opus",
            name: "All models",
            fetchedAt: referenceDate
        )])

        #expect(manager.activeSelection == nil)
        #expect(legacyActivity.content.state.availability == .unavailable)
        #expect(legacyActivity.content.state.selection == nil)

        let matching = makeSnapshot(
            provider: .claude,
            windowID: "sonnet",
            name: "Sonnet",
            utilization: 55,
            fetchedAt: referenceDate.addingTimeInterval(60)
        )
        await manager.refresh(from: [matching])

        #expect(
            manager.activeSelection
                == UsageActivitySelection(provider: .claude, windowID: "sonnet")
        )
        #expect(legacyActivity.content.state.percentUsed == 55)
        #expect(legacyActivity.content.state.availability == .available)
    }

    @Test func relaunchRetainsNewestActivityAndEndsDuplicates() async {
        let oldSelection = UsageActivitySelection(provider: .claude, windowID: "session")
        let newSelection = UsageActivitySelection(provider: .cursor, windowID: "cursor.total")
        let old = existingActivity(id: "old", selection: oldSelection, fetchedAt: referenceDate)
        let newest = existingActivity(
            id: "newest",
            selection: newSelection,
            fetchedAt: referenceDate.addingTimeInterval(60)
        )
        let client = FakeLiveActivityClient(activities: [old, newest])

        let manager = LiveActivityManager(client: client, now: { referenceDate })
        await eventually { old.endCount == 1 }

        #expect(manager.isRunning)
        #expect(manager.activeSelection == newSelection)
        #expect(old.endCount == 1)
        #expect(newest.endCount == 0)
    }

    @Test func externalDismissalClearsPublishedState() async {
        let selection = UsageActivitySelection(provider: .codex, windowID: "codex-weekly")
        let activity = existingActivity(id: "active", selection: selection, fetchedAt: referenceDate)
        let client = FakeLiveActivityClient(activities: [activity])
        let manager = LiveActivityManager(client: client, now: { referenceDate })

        activity.sendLifecycleState(.dismissed)
        await eventually { !manager.isRunning }

        #expect(!manager.isRunning)
        #expect(manager.activeSelection == nil)
        #expect(manager.activeWindowDisplayName == nil)
    }

    @Test func stopEndsCurrentAndOrphanActivitiesAndIsIdempotent() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .claude, windowID: "session")
        await manager.activate(
            selection: selection,
            from: [makeSnapshot(provider: .claude, windowID: selection.windowID)]
        )
        let current = try #require(client.requestedActivities.first)
        let orphan = existingActivity(
            id: "orphan",
            selection: UsageActivitySelection(provider: .cursor, windowID: "cursor.total"),
            fetchedAt: referenceDate
        )
        client.storedActivities.append(orphan)

        await manager.stop()
        await manager.stop()

        #expect(current.endCount == 1)
        #expect(orphan.endCount == 1)
        #expect(!manager.isRunning)
        #expect(manager.activeSelection == nil)
    }

    @Test func autoPinStartsSoonestShortWindowAtLimit() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let snapshots = [
            makeWaitingRoomSnapshot(
                provider: .claude,
                windowID: "session",
                name: "Current session",
                resetsAt: referenceDate.addingTimeInterval(3_600)
            ),
            makeWaitingRoomSnapshot(
                provider: .codex,
                windowID: "codexFiveHour",
                name: "5-hour limit",
                resetsAt: referenceDate.addingTimeInterval(1_800)
            ),
        ]

        await manager.reconcile(from: snapshots, autoPinAtLimit: true, canStart: true)

        #expect(client.requestCount == 1)
        #expect(manager.activeSelection?.provider == .codex)
        #expect(manager.activeWindowDisplayName == "5-hour limit")
    }

    @Test func autoPinDoesNotStartInBackgroundOrWhenDisabled() async {
        let snapshots = [makeWaitingRoomSnapshot()]

        let backgroundClient = FakeLiveActivityClient()
        let backgroundManager = LiveActivityManager(client: backgroundClient, now: { referenceDate })
        await backgroundManager.reconcile(from: snapshots, autoPinAtLimit: true, canStart: false)
        #expect(backgroundClient.requestCount == 0)

        let disabledClient = FakeLiveActivityClient()
        let disabledManager = LiveActivityManager(client: disabledClient, now: { referenceDate })
        await disabledManager.reconcile(from: snapshots, autoPinAtLimit: false, canStart: true)
        #expect(disabledClient.requestCount == 0)
    }

    @Test func autoPinSkipsWeeklyExtraUsageAndDismissedWindows() async throws {
        let weekly = makeWaitingRoomSnapshot(
            windowID: "opus",
            name: "All models",
            duration: 7 * 24 * 3600
        )
        let extra = makeWaitingRoomSnapshot(utilization: 115)
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })

        await manager.reconcile(from: [weekly], autoPinAtLimit: true, canStart: true)
        await manager.reconcile(from: [extra], autoPinAtLimit: true, canStart: true)
        #expect(client.requestCount == 0)

        let eligible = [makeWaitingRoomSnapshot()]
        await manager.reconcile(from: eligible, autoPinAtLimit: true, canStart: true)
        #expect(client.requestCount == 1)
        let activity = try #require(client.requestedActivities.first)
        activity.sendLifecycleState(.dismissed)
        await eventually { !manager.isRunning }

        await manager.reconcile(from: eligible, autoPinAtLimit: true, canStart: true)
        #expect(client.requestCount == 1)

        manager.clearDismissals()
        await manager.reconcile(from: eligible, autoPinAtLimit: true, canStart: true)
        #expect(client.requestCount == 2)
    }

    @Test func autoPinSkipsDismissedCandidateAndPinsNext() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let sooner = makeWaitingRoomSnapshot(
            provider: .codex,
            windowID: "codexFiveHour",
            name: "5-hour limit",
            resetsAt: referenceDate.addingTimeInterval(1_800)
        )
        let later = makeWaitingRoomSnapshot(
            provider: .claude,
            windowID: "session",
            name: "Current session",
            resetsAt: referenceDate.addingTimeInterval(3_600)
        )

        await manager.reconcile(from: [sooner], autoPinAtLimit: true, canStart: true)
        let activity = try #require(client.requestedActivities.first)
        activity.sendLifecycleState(.dismissed)
        await eventually { !manager.isRunning }

        await manager.reconcile(from: [sooner, later], autoPinAtLimit: true, canStart: true)

        #expect(client.requestCount == 2)
        #expect(manager.activeSelection?.provider == .claude)
    }

    @Test func stopPreventsAutoPinUntilDismissalCleared() async {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let snapshots = [makeWaitingRoomSnapshot()]

        await manager.reconcile(from: snapshots, autoPinAtLimit: true, canStart: true)
        await manager.stop()
        await manager.reconcile(from: snapshots, autoPinAtLimit: true, canStart: true)

        #expect(client.requestCount == 1)
        #expect(!manager.isRunning)
    }

    @Test func appConnectionRevocationImmediatelyEndsLiveActivities() async throws {
        let client = FakeLiveActivityClient()
        let manager = LiveActivityManager(client: client, now: { referenceDate })
        let selection = UsageActivitySelection(provider: .codex, windowID: "codex-weekly")
        await manager.activate(
            selection: selection,
            from: [makeSnapshot(provider: .codex, windowID: selection.windowID)]
        )
        let activity = try #require(client.requestedActivities.first)
        let testDefaults = TestUserDefaults()
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            liveActivityManager: manager,
            defaults: testDefaults.defaults
        )

        await viewModel.revokeAppConnection()

        #expect(activity.endCount == 1)
        #expect(!manager.isRunning)
        #expect(manager.activeSelection == nil)
    }

    private func makeWaitingRoomSnapshot(
        provider: Provider = .claude,
        windowID: UsageWindowID = "session",
        name: String = "Current session",
        utilization: Double = 100,
        resetsAt: Date? = nil,
        duration: TimeInterval = 5 * 3600
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(
                    utilization: utilization,
                    resetsAt: resetsAt ?? referenceDate.addingTimeInterval(3_600),
                    windowID: windowID,
                    displayName: name,
                    totalDuration: duration
                ),
            ],
            fetchedAt: referenceDate
        )
    }

    private func makeSnapshot(
        provider: Provider,
        windowID: UsageWindowID,
        name: String = "Usage",
        utilization: Double = 25,
        resetsAt: Date? = nil,
        fetchedAt: Date? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(
                    utilization: utilization,
                    resetsAt: resetsAt ?? referenceDate.addingTimeInterval(3_600),
                    windowID: windowID,
                    displayName: name,
                    totalDuration: 7 * 24 * 3_600
                ),
            ],
            fetchedAt: fetchedAt ?? referenceDate
        )
    }

    private func existingActivity(
        id: String,
        selection: UsageActivitySelection,
        fetchedAt: Date
    ) -> FakeLiveActivityHandle {
        let state = AgentUsageLiveActivityAttributes.ContentState(
            percentUsed: 25,
            timeUntilReset: "1h",
            statusRaw: UsageStatus.onTrack.rawValue,
            selection: selection,
            windowDisplayName: "Usage",
            resetsAt: referenceDate.addingTimeInterval(3_600),
            fetchedAt: fetchedAt,
            availabilityRaw: UsageActivityAvailability.available.rawValue
        )
        return FakeLiveActivityHandle(
            id: id,
            attributes: AgentUsageLiveActivityAttributes(selectedMetric: "Usage"),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func eventually(
        attempts: Int = 20,
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeLiveActivityHandle: LiveActivityHandle {
    let id: String
    let attributes: AgentUsageLiveActivityAttributes
    var content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>
    var lifecycleState: LiveActivityLifecycleState
    private let lifecycleStream: AsyncStream<LiveActivityLifecycleState>
    private let lifecycleContinuation: AsyncStream<LiveActivityLifecycleState>.Continuation

    private(set) var updates: [ActivityContent<AgentUsageLiveActivityAttributes.ContentState>] = []
    private(set) var endCount = 0

    init(
        id: String,
        attributes: AgentUsageLiveActivityAttributes,
        content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>,
        lifecycleState: LiveActivityLifecycleState = .active
    ) {
        self.id = id
        self.attributes = attributes
        self.content = content
        self.lifecycleState = lifecycleState
        let stream = AsyncStream.makeStream(of: LiveActivityLifecycleState.self)
        self.lifecycleStream = stream.stream
        self.lifecycleContinuation = stream.continuation
    }

    func update(_ content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>) async {
        updates.append(content)
        self.content = content
    }

    func endImmediately() async {
        guard lifecycleState == .active || lifecycleState == .stale else { return }
        endCount += 1
        lifecycleState = .ended
        lifecycleContinuation.yield(.ended)
    }

    func stateUpdates() -> AsyncStream<LiveActivityLifecycleState> {
        lifecycleStream
    }

    func sendLifecycleState(_ state: LiveActivityLifecycleState) {
        lifecycleState = state
        lifecycleContinuation.yield(state)
    }
}

@MainActor
private final class FakeLiveActivityClient: LiveActivityClient {
    var areActivitiesEnabled = true
    var storedActivities: [FakeLiveActivityHandle]
    var requestError: Error?
    private(set) var requestCount = 0
    private(set) var requestedActivities: [FakeLiveActivityHandle] = []

    init(activities: [FakeLiveActivityHandle] = []) {
        self.storedActivities = activities
    }

    var activities: [any LiveActivityHandle] {
        storedActivities
    }

    func request(
        attributes: AgentUsageLiveActivityAttributes,
        content: ActivityContent<AgentUsageLiveActivityAttributes.ContentState>
    ) throws -> any LiveActivityHandle {
        requestCount += 1
        if let requestError { throw requestError }
        let activity = FakeLiveActivityHandle(
            id: "requested-\(requestCount)",
            attributes: attributes,
            content: content
        )
        storedActivities.append(activity)
        requestedActivities.append(activity)
        return activity
    }
}

private enum FakeActivityError: LocalizedError {
    case requestFailed

    var errorDescription: String? { "Test request failed" }
}
#endif
