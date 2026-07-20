//
//  NotificationPermissionState.swift
//  AgentUsage
//

import Foundation

/// App-facing notification authorization state shared by macOS and iOS.
nonisolated enum NotificationPermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied

    var canDeliverNotifications: Bool {
        self == .authorized
    }
}

/// Result of sending the synthetic notification used by Settings diagnostics.
nonisolated enum NotificationTestResult: Equatable, Sendable {
    case sent
    case permissionDenied
    case failed(String)
}
