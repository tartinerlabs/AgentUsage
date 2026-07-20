//
//  NotificationServiceProtocol.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit

/// Protocol for sending usage threshold notifications
/// Enables dependency injection and testing with mock implementations
protocol NotificationServiceProtocol: Actor {
    /// Request notification permissions from the user
    /// - Returns: True if permission was granted
    func requestPermission() async -> Bool

    /// Check if notification permissions are granted
    /// - Returns: True if authorized
    func checkPermission() async -> Bool

    /// Get the current app-facing notification permission state.
    func permissionState() async -> NotificationPermissionState

    /// Check for threshold crossings and send notifications
    /// - Parameters:
    ///   - oldSnapshot: Previous usage snapshot (nil on first fetch)
    ///   - newSnapshot: Current usage snapshot
    func checkThresholdCrossings(
        oldSnapshot: UsageSnapshot?,
        newSnapshot: UsageSnapshot
    ) async

    /// Send a synthetic test notification that does not depend on usage data.
    func sendTestNotification() async -> NotificationTestResult
}
