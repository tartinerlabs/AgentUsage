//
//  UsageCalculations.swift
//  ClaudeMeterKit
//
//  Shared usage calculation utilities to avoid duplication across services
//

import Foundation

/// Shared usage calculation utilities
public enum UsageCalculations {
    /// Compute the overall worst status across multiple usage windows
    /// - Parameter windows: Array of optional usage windows to evaluate
    /// - Returns: The worst status (critical > warning > onTrack), defaulting to onTrack if no windows
    public static func overallStatus(from windows: [UsageWindow?]) -> UsageStatus {
        let statuses = windows.compactMap { $0?.status }

        // Return worst status: critical > warning > onTrack
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning) { return .warning }
        return .onTrack
    }

    /// Compute the overall worst status from a usage snapshot
    /// - Parameter snapshot: The usage snapshot to evaluate
    /// - Returns: The worst status across all windows
    public static func overallStatus(from snapshot: UsageSnapshot?) -> UsageStatus {
        guard let snapshot else { return .onTrack }
        return overallStatus(from: [snapshot.session, snapshot.opus, snapshot.sonnet])
    }
}
