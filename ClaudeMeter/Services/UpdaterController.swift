//
//  UpdaterController.swift
//  ClaudeMeter
//

#if os(macOS)
internal import Combine
import Foundation
import Sparkle
import UserNotifications

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
        Task { @MainActor in
            controller?.handleCheckResult(.updateAvailable(version: version))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            controller?.handleCheckResult(.upToDate)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            controller?.handleCheckResult(.error(message: message))
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            controller?.handleCheckResult(.error(message: message))
        }
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
    }

    /// Manually trigger an update check
    func checkForUpdates() {
        isChecking = true
        lastCheckResult = nil
        updaterController.checkForUpdates(nil)
    }

    /// Handle check result from delegate
    func handleCheckResult(_ result: UpdateCheckResult) {
        isChecking = false
        lastCheckResult = result

        // Auto-dismiss result after delay (except for errors)
        if case .upToDate = result {
            Task {
                try? await Task.sleep(for: .seconds(5))
                if lastCheckResult == .upToDate {
                    lastCheckResult = nil
                }
            }
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
