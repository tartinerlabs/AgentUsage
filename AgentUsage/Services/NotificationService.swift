//
//  NotificationService.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit
import OSLog
import UserNotifications

protocol UserNotificationCenterClient: Actor {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func permissionState() async -> NotificationPermissionState
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationIdentifiers() async -> [String]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
}

actor SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        return Self.permissionState(for: settings.authorizationStatus)
    }

    nonisolated static func permissionState(
        for authorizationStatus: UNAuthorizationStatus
    ) -> NotificationPermissionState {
        switch authorizationStatus {
        #if os(iOS)
        case .authorized, .provisional, .ephemeral:
            return .authorized
        #else
        case .authorized, .provisional:
            return .authorized
        #endif
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

actor NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    private let notificationCenter: any UserNotificationCenterClient
    private nonisolated let settingsProvider: @Sendable () -> NotificationSettings

    /// Identifies one window's reset period. Keeping `resetsAt` as a field rather than
    /// baking it into a string lets eviction order by recency instead of by name.
    private struct WindowPeriodKey: Hashable {
        let name: String
        let resetsAt: TimeInterval
    }

    // Track notified thresholds per window type and reset time to avoid duplicates
    private var notifiedThresholds: [WindowPeriodKey: Set<Int>] = [:]

    // Track whether we've already notified about extra usage activation
    private var notifiedExtraUsage: Bool = false

    init(
        notificationCenter: any UserNotificationCenterClient = SystemUserNotificationCenterClient(),
        settingsProvider: @escaping @Sendable () -> NotificationSettings = {
            NotificationSettings.load()
        }
    ) {
        self.notificationCenter = notificationCenter
        self.settingsProvider = settingsProvider
    }

    // MARK: - Settings

    /// Get current notification settings
    nonisolated var settings: NotificationSettings {
        settingsProvider()
    }

    /// Update notification settings
    func updateSettings(_ newSettings: NotificationSettings) {
        newSettings.save()
    }

    // MARK: - Helpers

    /// Truncate date to second precision to avoid false positives from API timestamp variations
    private func dateToSeconds(_ date: Date) -> TimeInterval {
        return floor(date.timeIntervalSince1970)
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            Logger.notifications.error("Notification permission error: \(error.localizedDescription)")
            return false
        }
    }

    func checkPermission() async -> Bool {
        await permissionState().canDeliverNotifications
    }

    func permissionState() async -> NotificationPermissionState {
        await notificationCenter.permissionState()
    }

    // MARK: - Threshold Notifications

    /// Check for threshold crossings and send notifications
    /// - Parameters:
    ///   - oldSnapshot: Previous usage snapshot (nil on first fetch)
    ///   - newSnapshot: Current usage snapshot
    func checkThresholdCrossings(
        oldSnapshot: UsageSnapshot?,
        newSnapshot: UsageSnapshot
    ) async {
        let currentSettings = settings

        // Check each usage window based on settings
        if currentSettings.notifySession {
            await checkWindow(
                name: newSnapshot.session.displayName,
                oldUsage: oldSnapshot?.session,
                newUsage: newSnapshot.session,
                settings: currentSettings
            )
        }

        if currentSettings.notifyOpus {
            await checkWindow(
                name: newSnapshot.opus.displayName,
                oldUsage: oldSnapshot?.opus,
                newUsage: newSnapshot.opus,
                settings: currentSettings
            )
        }

        if let newSonnet = newSnapshot.sonnet, currentSettings.notifySonnet {
            await checkWindow(
                name: newSonnet.displayName,
                oldUsage: oldSnapshot?.sonnet,
                newUsage: newSonnet,
                settings: currentSettings
            )
        }

        if let newDesign = newSnapshot.design, currentSettings.notifyDesign {
            await checkWindow(
                name: newDesign.displayName,
                oldUsage: oldSnapshot?.design,
                newUsage: newDesign,
                settings: currentSettings
            )
        }

        if let newFable = newSnapshot.fable, currentSettings.notifyFable {
            await checkWindow(
                name: newFable.displayName,
                oldUsage: oldSnapshot?.fable,
                newUsage: newFable,
                settings: currentSettings
            )
        }

        // Check for extra usage activation
        if currentSettings.notifyExtraUsage {
            let wasActive = oldSnapshot?.isExtraUsageActive ?? false
            let isActive = newSnapshot.isExtraUsageActive

            if oldSnapshot == nil {
                // First-observation suppression applies to extra usage too. Remember
                // the observed state so a later deactivation can re-arm the alert.
                notifiedExtraUsage = isActive
            } else if !wasActive && isActive && !notifiedExtraUsage {
                await sendExtraUsageNotification()
                notifiedExtraUsage = true
            } else if !isActive {
                notifiedExtraUsage = false
            }
        }
    }

    private func checkWindow(
        name: String,
        oldUsage: UsageWindow?,
        newUsage: UsageWindow,
        settings: NotificationSettings
    ) async {
        let newPercent = newUsage.percentUsed
        let oldPercent = oldUsage?.percentUsed ?? 0

        // Create unique key for this window's reset period (using second precision)
        let windowKey = WindowPeriodKey(name: name, resetsAt: dateToSeconds(newUsage.resetsAt))

        // Reset alerts are scheduled against `resetsAt` rather than observed on
        // the next snapshot. Still drop threshold-dedup state for the old period.
        if let oldUsage, dateToSeconds(oldUsage.resetsAt) != dateToSeconds(newUsage.resetsAt) {
            let oldKey = WindowPeriodKey(name: name, resetsAt: dateToSeconds(oldUsage.resetsAt))
            notifiedThresholds.removeValue(forKey: oldKey)
        }

        // Initialize set for this window if needed
        // Pre-populate already-passed thresholds to prevent false "crossing" notifications on first launch
        if notifiedThresholds[windowKey] == nil {
            notifiedThresholds[windowKey] = []
            // Suppress alerts only when this is the first snapshot the app has ever
            // observed. If a cached old snapshot exists, preserve the crossing so an
            // iOS process relaunch does not lose the notification.
            if oldUsage == nil {
                for threshold in settings.thresholds where newPercent >= threshold {
                    notifiedThresholds[windowKey]?.insert(threshold)
                }
            }
        }

        // Check each configured threshold
        for threshold in settings.thresholds {
            // Only notify if:
            // 1. We crossed this threshold (old < threshold, new >= threshold)
            // 2. We haven't already notified for this threshold in this window
            let crossed = oldPercent < threshold && newPercent >= threshold
            let alreadyNotified = notifiedThresholds[windowKey]?.contains(threshold) ?? false

            if crossed && !alreadyNotified {
                await sendNotification(windowName: name, threshold: threshold, usage: newUsage)
                notifiedThresholds[windowKey]?.insert(threshold)
            }
        }

        // Clean up old window keys (keep the 10 most recent reset periods). Evicting by
        // reset time rather than by key ordering keeps every live window's dedupe state.
        if notifiedThresholds.count > 10 {
            let staleKeys = notifiedThresholds.keys
                .sorted { $0.resetsAt < $1.resetsAt }
                .prefix(notifiedThresholds.count - 10)
            for key in staleKeys {
                notifiedThresholds.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Test Notifications

    func sendTestNotification() async -> NotificationTestResult {
        switch await permissionState() {
        case .notDetermined:
            let granted = await requestPermission()
            if !granted {
                return await permissionState() == .denied
                    ? .permissionDenied
                    : .failed("Notification permission could not be granted.")
            }
        case .denied:
            return .permissionDenied
        case .authorized:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "Usage alerts are working correctly."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
            return .sent
        } catch {
            Logger.notifications.error("Failed to send test notification: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Scheduled Reset Notifications

    func armResetNotifications(
        from snapshots: [ProviderUsageSnapshot],
        now: Date = Date()
    ) async {
        let hasPermission = await checkPermission()
        guard hasPermission, settings.notifyOnReset else {
            await cancelResetNotifications()
            return
        }

        let pending = await notificationCenter.pendingNotificationIdentifiers()
        let pendingReset = Set(pending.filter { $0.hasPrefix(Self.resetNotificationPrefix) })
        let desired = UsageWaitingRoom.resetAlertCandidates(from: snapshots, now: now)
        let desiredIDs = Set(desired.map(\.resetNotificationIdentifier))

        let stale = pendingReset.subtracting(desiredIDs)
        if !stale.isEmpty {
            await notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        for candidate in desired {
            let identifier = candidate.resetNotificationIdentifier
            if pendingReset.contains(identifier) { continue }
            let interval = candidate.window.resetsAt.timeIntervalSince(now)
            guard interval > 0 else { continue }
            await sendScheduledResetNotification(
                identifier: identifier,
                providerName: candidate.provider.displayName,
                windowName: candidate.window.displayName,
                timeInterval: max(interval, 1)
            )
        }
    }

    func cancelResetNotifications() async {
        let pending = await notificationCenter.pendingNotificationIdentifiers()
        let resetIDs = pending.filter { $0.hasPrefix(Self.resetNotificationPrefix) }
        guard !resetIDs.isEmpty else { return }
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: resetIDs)
    }

    private static let resetNotificationPrefix = "reset."

    #if DEBUG
    func sendTestResetNotification() async {
        let hasPermission = await checkPermission()
        guard hasPermission else {
            _ = await requestPermission()
            return
        }
        await sendResetNotification(windowName: "Session")
    }
    #endif

    private func sendNotification(
        windowName: String,
        threshold: Int,
        usage: UsageWindow
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "\(windowName) Usage: \(threshold)%"

        let windowDescription: String
        switch usage.windowType {
        case .session, .codexFiveHour:
            windowDescription = "5-hour session"
        case .openCodeGoFiveHour:
            windowDescription = "rolling"
        case .opus, .sonnet, .design, .fable, .codexWeekly, .openCodeGoWeekly:
            windowDescription = "weekly"
        case .openCodeGoMonthly:
            windowDescription = "monthly"
        case .custom:
            windowDescription = usage.displayName.lowercased()
        }

        if threshold == 100 {
            content.body = "You've reached your \(windowDescription) limit. \(usage.resetDescription())."
        } else {
            content.body = "You've used \(threshold)% of your \(windowDescription) limit."
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Logger.notifications.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    private func sendExtraUsageNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Extra Usage Started"
        content.body = "You've exceeded your plan limit. Usage is now billed at API rates."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Logger.notifications.error("Failed to send extra usage notification: \(error.localizedDescription)")
        }
    }

    private func sendScheduledResetNotification(
        identifier: String,
        providerName: String,
        windowName: String,
        timeInterval: TimeInterval
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "\(providerName) \(windowName) reset"
        content.body = "Your \(windowName.lowercased()) limit has reset."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Logger.notifications.error("Failed to schedule reset notification: \(error.localizedDescription)")
        }
    }

    private func sendResetNotification(windowName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "\(windowName) Usage Reset"
        content.body = "Your \(windowName.lowercased()) limit has reset."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Logger.notifications.error("Failed to send reset notification: \(error.localizedDescription)")
        }
    }
}
