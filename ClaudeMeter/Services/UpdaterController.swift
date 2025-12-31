//
//  UpdaterController.swift
//  ClaudeMeter
//

internal import Combine
import Foundation
import Sparkle

/// Wrapper around Sparkle's SPUStandardUpdaterController for SwiftUI integration.
/// This class manages automatic update checks and provides a simple interface for manual checks.
@MainActor
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater can check for updates (enabled and not already checking)
    @Published var canCheckForUpdates = false

    init() {
        // Create the standard updater controller with default user driver and no delegate
        // The updater will automatically check for updates based on user preferences
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates changes
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually trigger an update check
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}


