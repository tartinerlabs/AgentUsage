//
//  UpdaterController.swift
//  ClaudeMeter
//

#if os(macOS)
internal import Combine
import Foundation
import Sparkle
import UserNotifications

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

// MARK: - Updater Controller

/// Wrapper around Sparkle's SPUStandardUpdaterController for SwiftUI integration.
/// This class manages automatic update checks and provides a simple interface for manual checks.
/// Implements gentle reminders for background (menu bar) apps per Sparkle documentation.
@MainActor
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate: UpdaterUserDriverDelegate

    /// Whether the updater can check for updates (enabled and not already checking)
    @Published var canCheckForUpdates = false

    /// Whether an update is available and waiting for user attention
    @Published var updateAvailable = false

    init() {
        // Create delegate first
        userDriverDelegate = UpdaterUserDriverDelegate()

        // Create the updater controller with delegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )

        // Link delegate back to controller
        userDriverDelegate.controller = self

        // Observe canCheckForUpdates changes
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually trigger an update check
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
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
