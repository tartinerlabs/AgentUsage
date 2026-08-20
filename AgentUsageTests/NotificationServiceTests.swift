//
//  NotificationServiceTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
import UserNotifications
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("NotificationService")
struct NotificationServiceTests {
    @Test func permissionStatesMapToDeliverability() {
        #expect(SystemUserNotificationCenterClient.permissionState(for: .notDetermined) == .notDetermined)
        #expect(SystemUserNotificationCenterClient.permissionState(for: .denied) == .denied)
        #expect(SystemUserNotificationCenterClient.permissionState(for: .authorized) == .authorized)
        #expect(SystemUserNotificationCenterClient.permissionState(for: .provisional) == .authorized)
        #if os(iOS)
        #expect(SystemUserNotificationCenterClient.permissionState(for: .ephemeral) == .authorized)
        #endif
    }

    @Test func firstSnapshotAboveThresholdDoesNotAlert() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(center: center)

        await service.checkThresholdCrossings(
            oldSnapshot: nil,
            newSnapshot: snapshot(session: 80)
        )

        #expect(await center.notifications().isEmpty)
    }

    @Test func cachedSnapshotCrossingAlertsAfterServiceRelaunch() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(center: center)
        let reset = Date().addingTimeInterval(3_600)

        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 20, sessionReset: reset),
            newSnapshot: snapshot(session: 30, sessionReset: reset)
        )

        let notifications = await center.notifications()
        #expect(notifications.map(\.title) == ["Current session Usage: 25%"])
    }

    @Test func repeatedCrossingDoesNotDuplicateAlert() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(center: center)
        let reset = Date().addingTimeInterval(3_600)
        let oldSnapshot = snapshot(session: 20, sessionReset: reset)
        let newSnapshot = snapshot(session: 30, sessionReset: reset)

        await service.checkThresholdCrossings(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)
        await service.checkThresholdCrossings(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)

        #expect(await center.notifications().count == 1)
    }

    @Test func snapshotComparisonNoLongerFiresResetAlerts() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyOnReset: true)
        )

        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(
                session: 95,
                sessionReset: Date().addingTimeInterval(-60)
            ),
            newSnapshot: snapshot(
                session: 10,
                sessionReset: Date().addingTimeInterval(3_600)
            )
        )

        #expect(await center.notifications().isEmpty)
    }

    @Test func nearLimitWindowSchedulesResetAlert() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyOnReset: true)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let resetsAt = now.addingTimeInterval(3_600)

        await service.armResetNotifications(
            from: [providerSnapshot(provider: .claude, utilization: 95, resetsAt: resetsAt, type: .session, now: now)],
            now: now
        )

        let notifications = await center.notifications()
        #expect(notifications.map(\.title) == ["Claude Current session reset"])
        #expect(notifications.first?.identifier == "reset.claude.session.2000003600")
        #expect(notifications.first?.triggerInterval == 3_600)
        #expect(await center.pendingIdentifiers() == ["reset.claude.session.2000003600"])
    }

    @Test func resetAlertSkipsBelowThresholdExpiredAndDisabled() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let future = now.addingTimeInterval(3_600)

        let below = RecordingUserNotificationCenterClient()
        await makeService(
            center: below,
            settings: settings(thresholds: [], notifyOnReset: true)
        ).armResetNotifications(
            from: [providerSnapshot(provider: .claude, utilization: 80, resetsAt: future, type: .session, now: now)],
            now: now
        )
        #expect(await below.notifications().isEmpty)

        let expired = RecordingUserNotificationCenterClient()
        await makeService(
            center: expired,
            settings: settings(thresholds: [], notifyOnReset: true)
        ).armResetNotifications(
            from: [providerSnapshot(
                provider: .codex,
                utilization: 100,
                resetsAt: now.addingTimeInterval(-60),
                type: .codexFiveHour,
                now: now
            )],
            now: now
        )
        #expect(await expired.notifications().isEmpty)

        let disabled = RecordingUserNotificationCenterClient()
        await makeService(
            center: disabled,
            settings: settings(thresholds: [], notifyOnReset: false)
        ).armResetNotifications(
            from: [providerSnapshot(provider: .claude, utilization: 95, resetsAt: future, type: .session, now: now)],
            now: now
        )
        #expect(await disabled.notifications().isEmpty)
    }

    @Test func rearmingKeepsDueResetAlertsAfterWindowReset() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyOnReset: true)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let dueReset = now.addingTimeInterval(30)
        let nextPeriod = now.addingTimeInterval(5 * 3_600)
        let firstSnapshot = providerSnapshot(
            provider: .codex,
            utilization: 100,
            resetsAt: dueReset,
            type: .codexFiveHour,
            now: now
        )

        await service.armResetNotifications(from: [firstSnapshot], now: now)
        await service.armResetNotifications(from: [firstSnapshot], now: now)
        #expect(await center.notifications().count == 1)

        await service.armResetNotifications(
            from: [providerSnapshot(
                provider: .codex,
                utilization: 10,
                resetsAt: nextPeriod,
                type: .codexFiveHour,
                now: now
            )],
            now: now
        )

        #expect(await center.pendingIdentifiers() == ["reset.codex.codexFiveHour.2000000030"])
        #expect(await center.removedIdentifiers().isEmpty)
    }

    @Test func rearmingCancelsRecoveredWindowsStillFarFromReset() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyOnReset: true)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let laterReset = now.addingTimeInterval(3_600)
        await service.armResetNotifications(
            from: [providerSnapshot(
                provider: .claude,
                utilization: 95,
                resetsAt: laterReset,
                type: .session,
                now: now
            )],
            now: now
        )

        await service.armResetNotifications(
            from: [providerSnapshot(
                provider: .claude,
                utilization: 40,
                resetsAt: laterReset,
                type: .session,
                now: now
            )],
            now: now
        )

        #expect(await center.pendingIdentifiers().isEmpty)
        #expect(await center.removedIdentifiers() == ["reset.claude.session.2000003600"])
    }

    @Test func grokWindowsDoNotScheduleResetAlerts() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyOnReset: true)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        await service.armResetNotifications(
            from: [providerSnapshot(
                provider: .grok,
                utilization: 100,
                resetsAt: now.addingTimeInterval(3_600),
                type: .session,
                now: now
            )],
            now: now
        )

        #expect(await center.notifications().isEmpty)
    }

    @Test func extraUsageAlertsOncePerActivation() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyExtraUsage: true)
        )
        let reset = Date().addingTimeInterval(3_600)

        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 80, sessionReset: reset),
            newSnapshot: snapshot(session: 101, sessionReset: reset)
        )
        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 101, sessionReset: reset),
            newSnapshot: snapshot(session: 105, sessionReset: reset)
        )
        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 105, sessionReset: reset),
            newSnapshot: snapshot(session: 80, sessionReset: reset)
        )
        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 80, sessionReset: reset),
            newSnapshot: snapshot(session: 101, sessionReset: reset)
        )

        #expect(
            await center.notifications().map(\.title)
                == ["Extra Usage Started", "Extra Usage Started"]
        )
    }

    @Test func firstSnapshotWithExtraUsageDoesNotAlert() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(thresholds: [], notifyExtraUsage: true)
        )

        await service.checkThresholdCrossings(
            oldSnapshot: nil,
            newSnapshot: snapshot(session: 101)
        )

        #expect(await center.notifications().isEmpty)
    }

    @Test func disabledNotificationTypesDoNotAlert() async {
        let center = RecordingUserNotificationCenterClient()
        let service = makeService(
            center: center,
            settings: settings(
                thresholds: [25],
                notifySession: false,
                notifyOnReset: false,
                notifyExtraUsage: false
            )
        )

        await service.checkThresholdCrossings(
            oldSnapshot: snapshot(session: 20),
            newSnapshot: snapshot(session: 101)
        )

        #expect(await center.notifications().isEmpty)
    }

    @Test func testNotificationSendsImmediatelyAfterPermissionGrant() async {
        let center = RecordingUserNotificationCenterClient(
            permissionState: .notDetermined,
            grantsPermission: true
        )
        let service = makeService(center: center)

        let result = await service.sendTestNotification()

        #expect(result == .sent)
        #expect(await center.permissionRequestCount() == 1)
        #expect(await center.notifications().map(\.title) == ["Test Notification"])
        #expect(await center.notifications().first?.triggerInterval == nil)
    }

    @Test func settingsRoundTripThroughInjectedDefaults() {
        let testDefaults = TestUserDefaults()
        let expected = settings(
            thresholds: [50, 100],
            notifySession: false,
            notifyOnReset: false,
            notifyExtraUsage: false
        )

        expected.save(defaults: testDefaults.defaults)

        #expect(NotificationSettings.load(defaults: testDefaults.defaults) == expected)
    }

    private func makeService(
        center: RecordingUserNotificationCenterClient,
        settings configuredSettings: NotificationSettings? = nil
    ) -> NotificationService {
        let resolvedSettings = configuredSettings ?? settings()
        return NotificationService(
            notificationCenter: center,
            settingsProvider: { resolvedSettings }
        )
    }

    private func settings(
        thresholds: [Int] = [25, 50, 75, 100],
        notifySession: Bool = true,
        notifyOnReset: Bool = true,
        notifyExtraUsage: Bool = true
    ) -> NotificationSettings {
        NotificationSettings(
            thresholds: thresholds,
            notifySession: notifySession,
            notifyOpus: false,
            notifySonnet: false,
            notifyDesign: false,
            notifyFable: false,
            notifyOnReset: notifyOnReset,
            notifyExtraUsage: notifyExtraUsage
        )
    }

    private func providerSnapshot(
        provider: Provider,
        utilization: Double,
        resetsAt: Date,
        type: UsageWindowType,
        now: Date
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(utilization: utilization, resetsAt: resetsAt, windowType: type)
            ],
            fetchedAt: now
        )
    }

    private func snapshot(
        session: Double,
        sessionReset: Date = Date().addingTimeInterval(3_600)
    ) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: session,
                resetsAt: sessionReset,
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 0,
                resetsAt: Date().addingTimeInterval(7_200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )
    }
}

private actor RecordingUserNotificationCenterClient: UserNotificationCenterClient {
    struct RecordedNotification: Equatable, Sendable {
        let identifier: String
        let title: String
        let body: String
        let triggerInterval: TimeInterval?
    }

    private var currentPermissionState: NotificationPermissionState
    private let grantsPermission: Bool
    private var requests: [RecordedNotification] = []
    private var pending: [String: RecordedNotification] = [:]
    private var removed: [String] = []
    private var requestCount = 0

    init(
        permissionState: NotificationPermissionState = .authorized,
        grantsPermission: Bool = true
    ) {
        self.currentPermissionState = permissionState
        self.grantsPermission = grantsPermission
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestCount += 1
        currentPermissionState = grantsPermission ? .authorized : .denied
        return grantsPermission
    }

    func permissionState() async -> NotificationPermissionState {
        currentPermissionState
    }

    func add(_ request: UNNotificationRequest) async throws {
        let triggerInterval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
        let recorded = RecordedNotification(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            triggerInterval: triggerInterval
        )
        requests.append(recorded)
        if request.trigger != nil {
            pending[request.identifier] = recorded
        }
    }

    func pendingNotificationIdentifiers() async -> [String] {
        Array(pending.keys)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removed.append(contentsOf: identifiers)
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    func notifications() -> [RecordedNotification] {
        requests
    }

    func pendingIdentifiers() -> [String] {
        Array(pending.keys)
    }

    func removedIdentifiers() -> [String] {
        removed
    }

    func permissionRequestCount() -> Int {
        requestCount
    }
}
