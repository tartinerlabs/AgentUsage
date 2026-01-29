//
//  NotificationService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog
import UserNotifications

actor NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    // Track notified thresholds per window type and reset time to avoid duplicates
    private var notifiedThresholds: [String: Set<Int>] = [:]

    private init() {}

    // MARK: - Settings

    /// Get current notification settings
    nonisolated var settings: NotificationSettings {
        NotificationSettings.load()
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
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus == .authorized
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
                name: newSnapshot.session.windowType.displayName,
                oldUsage: oldSnapshot?.session,
                newUsage: newSnapshot.session,
                settings: currentSettings
            )
        }

        if currentSettings.notifyOpus {
            await checkWindow(
                name: newSnapshot.opus.windowType.displayName,
                oldUsage: oldSnapshot?.opus,
                newUsage: newSnapshot.opus,
                settings: currentSettings
            )
        }

        if let newSonnet = newSnapshot.sonnet, currentSettings.notifySonnet {
            await checkWindow(
                name: newSonnet.windowType.displayName,
                oldUsage: oldSnapshot?.sonnet,
                newUsage: newSonnet,
                settings: currentSettings
            )
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
        let windowKey = "\(name)-\(dateToSeconds(newUsage.resetsAt))"

        // Check if reset occurred (new reset time means new window)
        // Compare at second precision to avoid false positives from API timestamp variations
        if let oldUsage, dateToSeconds(oldUsage.resetsAt) != dateToSeconds(newUsage.resetsAt) {
            // Reset period changed, clear notified thresholds for old key
            let oldKey = "\(name)-\(dateToSeconds(oldUsage.resetsAt))"
            notifiedThresholds.removeValue(forKey: oldKey)

            // Enhanced guards for reset notification:
            // 1. Was near limit (>= 90%)
            // 2. Usage actually dropped (new < 50%) - prevents false notifications
            // 3. New reset is in future (sanity check)
            // 4. Reset notifications are enabled
            if settings.notifyOnReset
                && oldUsage.percentUsed >= 90
                && newPercent < 50
                && newUsage.resetsAt > Date() {
                await sendResetNotification(windowName: name)
            }
        }

        // Initialize set for this window if needed
        // Pre-populate already-passed thresholds to prevent false "crossing" notifications on first launch
        if notifiedThresholds[windowKey] == nil {
            notifiedThresholds[windowKey] = []
            // Mark thresholds already exceeded to avoid spurious notifications
            for threshold in settings.thresholds where newPercent >= threshold {
                notifiedThresholds[windowKey]?.insert(threshold)
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

        // Clean up old window keys (keep only last 10)
        if notifiedThresholds.count > 10 {
            let sortedKeys = notifiedThresholds.keys.sorted()
            for key in sortedKeys.prefix(notifiedThresholds.count - 10) {
                notifiedThresholds.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Test Notifications

    func sendTestNotification() async {
        let hasPermission = await checkPermission()
        guard hasPermission else {
            _ = await requestPermission()
            return
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
        } catch {
            Logger.notifications.error("Failed to send test notification: \(error.localizedDescription)")
        }
    }

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
        case .session:
            windowDescription = "5-hour session"
        case .opus, .sonnet:
            windowDescription = "weekly"
        }

        if threshold == 100 {
            content.body = "You've reached your \(windowDescription) limit. Resets in \(usage.timeUntilReset)."
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

    private func sendResetNotification(windowName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "\(windowName) Usage Reset"
        content.body = "Your \(windowName.lowercased()) limit has reset. You're back to 0%!"
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
#endif
