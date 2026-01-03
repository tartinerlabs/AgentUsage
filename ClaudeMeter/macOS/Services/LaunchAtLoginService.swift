//
//  LaunchAtLoginService.swift
//  ClaudeMeter
//

#if os(macOS)
internal import Combine
import Foundation
import ServiceManagement

/// Manages the app's launch at login setting using SMAppService.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    /// Whether the app is set to launch at login
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            updateLoginItem()
        }
    }

    private init() {
        // Read current status from SMAppService
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func updateLoginItem() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert on failure
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
#endif
