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

    @Test func nearLimitWindowResetAlerts() async {
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

        #expect(await center.notifications().map(\.title) == ["Current session Usage Reset"])
    }

    @Test func resetAlertGuardsRejectInvalidTransitions() async {
        let now = Date()
        let scenarios: [(oldPercent: Double, newPercent: Double, newReset: Date)] = [
            (80, 10, now.addingTimeInterval(3_600)),
            (95, 60, now.addingTimeInterval(3_600)),
            (95, 10, now.addingTimeInterval(-60)),
        ]

        for scenario in scenarios {
            let center = RecordingUserNotificationCenterClient()
            let service = makeService(
                center: center,
                settings: settings(thresholds: [], notifyOnReset: true)
            )
            await service.checkThresholdCrossings(
                oldSnapshot: snapshot(
                    session: scenario.oldPercent,
                    sessionReset: now.addingTimeInterval(-120)
                ),
                newSnapshot: snapshot(
                    session: scenario.newPercent,
                    sessionReset: scenario.newReset
                )
            )

            #expect(await center.notifications().isEmpty)
        }
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
        requests.append(RecordedNotification(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            triggerInterval: triggerInterval
        ))
    }

    func notifications() -> [RecordedNotification] {
        requests
    }

    func permissionRequestCount() -> Int {
        requestCount
    }
}
