//
//  UpdaterController.swift
//  ClaudeMeter
//

#if os(macOS)
internal import Combine
import Foundation
import os.log
import Sparkle
import UserNotifications

// MARK: - Logger

private let logger = Logger(subsystem: "com.tartinerlabs.ClaudeMeter", category: "Updater")

// MARK: - Update Check Result

/// Result of an update check operation
enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(version: String)
    case error(message: String)

    var message: String {
        switch self {
        case .upToDate:
            return "You're up to date!"
        case let .updateAvailable(version):
            return "Version \(version) available"
        case let .error(message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - User Driver Delegate

/// Delegate for gentle reminders in background (menu bar) apps.
/// This is a separate class to work around initialization constraints.
@MainActor
final class UpdaterUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    weak var controller: UpdaterController?

    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        controller?.handleUpdateAvailable(update)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        controller?.handleUserAttention()
    }

    func standardUserDriverWillFinishUpdateSession() {
        controller?.handleSessionFinished()
    }
}

// MARK: - Updater Delegate

/// Delegate to track update check lifecycle
@MainActor
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var controller: UpdaterController?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        logger.info("Found valid update: version \(version, privacy: .public)")
        Task { @MainActor in
            controller?.handleCheckResult(.updateAvailable(version: version))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        logger.info("No update found - app is up to date")
        Task { @MainActor in
            controller?.handleCheckResult(.upToDate)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let message = error.localizedDescription
        logger.error("Update check failed: \(message, privacy: .public)")
        Task { @MainActor in
            controller?.handleCheckResult(.error(message: message))
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let message = error.localizedDescription
        logger.error("Update check aborted: \(message, privacy: .public)")
        Task { @MainActor in
            controller?.handleCheckResult(.error(message: message))
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        let minutes = Int(delay / 60)
        logger.info("Next scheduled update check in \(minutes) minutes")
        Task { @MainActor in
            controller?.handleScheduledCheckPlanned(delay: delay)
        }
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("Application will relaunch for update installation")
    }

    nonisolated func updater(_ updater: SPUUpdater, userDidSkipThisVersion item: SUAppcastItem) {
        logger.info("User skipped version \(item.displayVersionString, privacy: .public)")
    }
}

// MARK: - Updater Controller

/// Wrapper around Sparkle's SPUStandardUpdaterController for SwiftUI integration.
/// This class manages automatic update checks and provides a simple interface for manual checks.
/// Implements gentle reminders for background (menu bar) apps per Sparkle documentation.
@MainActor
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate: UpdaterUserDriverDelegate
    private let updaterDelegate: UpdaterDelegate

    /// Whether the updater can check for updates (enabled and not already checking)
    @Published var canCheckForUpdates = false

    /// Whether an update is available and waiting for user attention
    @Published var updateAvailable = false

    /// Whether an update check is currently in progress
    @Published var isChecking = false

    /// Result of the last update check (nil if no check performed yet)
    @Published var lastCheckResult: UpdateCheckResult?

    /// Date of the last update check (from Sparkle's UserDefaults)
    @Published var lastCheckDate: Date?

    /// Date when next scheduled check will occur
    @Published var nextScheduledCheckDate: Date?

    /// Formatted description of last check date for UI
    var lastCheckDescription: String {
        guard let date = lastCheckDate else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    init() {
        // Create delegates first
        userDriverDelegate = UpdaterUserDriverDelegate()
        updaterDelegate = UpdaterDelegate()

        // Create the updater controller with delegates
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )

        // Link delegates back to controller
        userDriverDelegate.controller = self
        updaterDelegate.controller = self

        // Observe canCheckForUpdates changes
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Sync initial value (KVO publisher doesn't emit initial value)
        canCheckForUpdates = updaterController.updater.canCheckForUpdates

        // Read last check date from Sparkle's UserDefaults
        updateLastCheckDate()

        // Log configuration on startup
        logConfiguration()

        // Schedule initial background check for menu bar apps
        // Per Sparkle GitHub Issue #1163: Menu bar apps need explicit background check
        scheduleInitialBackgroundCheck()
    }

    // MARK: - Configuration Logging

    private func logConfiguration() {
        let updater = updaterController.updater
        logger.info("Sparkle configuration:")
        logger.info("  Feed URL: \(updater.feedURL?.absoluteString ?? "nil", privacy: .public)")
        logger.info("  Automatically checks: \(updater.automaticallyChecksForUpdates)")
        logger.info("  Check interval: \(Int(updater.updateCheckInterval / 3600)) hours")
        logger.info("  Can check now: \(updater.canCheckForUpdates)")
        if let lastCheck = lastCheckDate {
            logger.info("  Last check: \(lastCheck, privacy: .public)")
        } else {
            logger.info("  Last check: Never")
        }
    }

    // MARK: - Initial Background Check

    private func scheduleInitialBackgroundCheck() {
        Task {
            // Wait 30 seconds after app launch to avoid blocking startup
            try? await Task.sleep(for: .seconds(30))

            // Only proceed if automatic checks are enabled
            guard updaterController.updater.automaticallyChecksForUpdates else {
                logger.info("Automatic checks disabled, skipping initial background check")
                return
            }

            // Skip if we've checked recently (within last hour)
            if let lastCheck = lastCheckDate,
               Date().timeIntervalSince(lastCheck) < 3600 {
                logger.info("Recent check found (\(self.lastCheckDescription)), skipping initial background check")
                return
            }

            logger.info("Performing initial background check for menu bar app")
            checkForUpdatesInBackground()
        }
    }

    /// Manually trigger an update check (user-initiated, shows UI)
    func checkForUpdates() {
        logger.info("User-initiated update check started")
        isChecking = true
        lastCheckResult = nil
        updaterController.checkForUpdates(nil)
    }

    /// Perform a background (silent) update check
    /// This won't show UI unless an update is found
    /// Use this for automatic/scheduled checks in menu bar apps
    func checkForUpdatesInBackground() {
        logger.info("Background update check started")
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Handle check result from delegate
    func handleCheckResult(_ result: UpdateCheckResult) {
        isChecking = false
        lastCheckResult = result

        // Update last check date
        updateLastCheckDate()

        // Auto-dismiss all results after delay
        let delay: Duration = switch result {
        case .upToDate: .seconds(5)
        case .updateAvailable: .seconds(10)
        case .error: .seconds(8)
        }

        Task {
            try? await Task.sleep(for: delay)
            if lastCheckResult == result {
                lastCheckResult = nil
            }
        }
    }

    /// Handle scheduled check planned notification from delegate
    func handleScheduledCheckPlanned(delay: TimeInterval) {
        nextScheduledCheckDate = Date().addingTimeInterval(delay)
    }

    /// Read last check date from Sparkle's UserDefaults
    private func updateLastCheckDate() {
        // Sparkle stores this in UserDefaults with key "SULastCheckTime"
        if let lastCheck = UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date {
            lastCheckDate = lastCheck
        }
    }

    // MARK: - Delegate Handlers

    func handleUpdateAvailable(_ update: SUAppcastItem) {
        updateAvailable = true
        postUpdateNotification(version: update.displayVersionString)
    }

    func handleUserAttention() {
        updateAvailable = false
        removeUpdateNotification()
    }

    func handleSessionFinished() {
        updateAvailable = false
        lastCheckResult = nil
        removeUpdateNotification()
    }

    // MARK: - System Notifications

    private func postUpdateNotification(version: String) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "ClaudeMeter Update Available"
            content.body = "Version \(version) is ready to install."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "com.tartinerlabs.ClaudeMeter.update",
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }

    private func removeUpdateNotification() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["com.tartinerlabs.ClaudeMeter.update"])
    }
}
#endif
