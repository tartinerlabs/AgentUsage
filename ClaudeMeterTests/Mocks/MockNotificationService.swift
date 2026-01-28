//
//  MockNotificationService.swift
//  ClaudeMeterTests
//
//  Mock implementation of NotificationServiceProtocol for testing (macOS)
//

#if os(macOS)
import Foundation
@testable import ClaudeMeter
import ClaudeMeterKit

/// Mock notification service for testing
actor MockNotificationService: NotificationServiceProtocol {
    /// Configurable permission state
    var hasPermission = true

    /// Track notification requests
    private(set) var permissionRequestCount = 0
    private(set) var permissionCheckCount = 0
    private(set) var thresholdCheckCount = 0
    private(set) var testNotificationCount = 0

    /// Track threshold crossing calls
    private(set) var lastOldSnapshot: UsageSnapshot?
    private(set) var lastNewSnapshot: UsageSnapshot?

    func requestPermission() async -> Bool {
        permissionRequestCount += 1
        return hasPermission
    }

    func checkPermission() async -> Bool {
        permissionCheckCount += 1
        return hasPermission
    }

    func checkThresholdCrossings(
        oldSnapshot: UsageSnapshot?,
        newSnapshot: UsageSnapshot
    ) async {
        thresholdCheckCount += 1
        lastOldSnapshot = oldSnapshot
        lastNewSnapshot = newSnapshot
    }

    func sendTestNotification() async {
        testNotificationCount += 1
    }

    /// Reset mock state
    func reset() {
        hasPermission = true
        permissionRequestCount = 0
        permissionCheckCount = 0
        thresholdCheckCount = 0
        testNotificationCount = 0
        lastOldSnapshot = nil
        lastNewSnapshot = nil
    }
}
#endif
