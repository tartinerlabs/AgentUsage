//
//  NotificationService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    private let thresholds: [Int] = [25, 50, 75, 100]
    private let notificationCenter = UNUserNotificationCenter.current()

    // Track notified thresholds per window type and reset time to avoid duplicates
    private var notifiedThresholds: [String: Set<Int>] = [:]

    private init() {}

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("Notification permission error: \(error)")
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
        // Check each usage window
        await checkWindow(
            name: newSnapshot.session.windowType.displayName,
            oldUsage: oldSnapshot?.session,
            newUsage: newSnapshot.session
        )

        await checkWindow(
            name: newSnapshot.opus.windowType.displayName,
            oldUsage: oldSnapshot?.opus,
            newUsage: newSnapshot.opus
        )

        if let newSonnet = newSnapshot.sonnet {
            await checkWindow(
                name: newSonnet.windowType.displayName,
                oldUsage: oldSnapshot?.sonnet,
                newUsage: newSonnet
            )
        }
    }

    private func checkWindow(
        name: String,
        oldUsage: UsageWindow?,
        newUsage: UsageWindow
    ) async {
        let newPercent = newUsage.percentUsed
        let oldPercent = oldUsage?.percentUsed ?? 0

        // Create unique key for this window's reset period
        let windowKey = "\(name)-\(newUsage.resetsAt.timeIntervalSince1970)"

        // Check if reset occurred (new reset time means new window)
        if let oldUsage, oldUsage.resetsAt != newUsage.resetsAt {
            // Reset period changed, clear notified thresholds for old key
            let oldKey = "\(name)-\(oldUsage.resetsAt.timeIntervalSince1970)"
            notifiedThresholds.removeValue(forKey: oldKey)

            // If user was near/at limit before reset, notify them it's reset
            if oldUsage.percentUsed >= 90 {
                await sendResetNotification(windowName: name)
            }
        }

        // Initialize set for this window if needed
        if notifiedThresholds[windowKey] == nil {
            notifiedThresholds[windowKey] = []
        }

        // Check each threshold
        for threshold in thresholds {
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
            print("Failed to send test notification: \(error)")
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
            print("Failed to send notification: \(error)")
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
            print("Failed to send reset notification: \(error)")
        }
    }
}
#endif
