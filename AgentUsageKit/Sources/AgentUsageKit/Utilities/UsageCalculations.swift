//
//  UsageCalculations.swift
//  AgentUsageKit
//
//  Shared usage calculation utilities to avoid duplication across services
//

import Foundation

/// Shared usage calculation utilities
public enum UsageCalculations {
    /// Compute the overall worst status across multiple usage windows
    /// - Parameter windows: Array of optional usage windows to evaluate
    /// - Parameter now: Reference date used for expiry and pace calculations
    /// - Returns: The worst status (critical > warning > onTrack), defaulting to onTrack if no windows
    public static func overallStatus(
        from windows: [UsageWindow?],
        asOf now: Date = Date()
    ) -> UsageStatus {
        let statuses = windows.compactMap { $0?.status(from: now) }

        // Return worst status: critical > warning > onTrack
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning) { return .warning }
        return .onTrack
    }

    /// Compute the overall worst status from a usage snapshot
    /// - Parameter snapshot: The usage snapshot to evaluate
    /// - Parameter now: Reference date used for expiry and pace calculations
    /// - Returns: The worst status across all windows
    public static func overallStatus(
        from snapshot: UsageSnapshot?,
        asOf now: Date = Date()
    ) -> UsageStatus {
        guard let snapshot else { return .onTrack }
        return overallStatus(
            from: [snapshot.session, snapshot.opus, snapshot.sonnet, snapshot.design, snapshot.fable],
            asOf: now
        )
    }

    /// Compute the overall worst status across Claude and every other monitored provider.
    ///
    /// Surfaces that present a single "how bad is it" indicator for the whole app must
    /// use this: reading Claude alone reports on-track while another provider is at 98%.
    public static func overallStatus(
        from snapshot: UsageSnapshot?,
        providerSnapshots: some Sequence<ProviderUsageSnapshot>,
        asOf now: Date = Date()
    ) -> UsageStatus {
        var windows: [UsageWindow?] = []
        if let snapshot {
            windows.append(contentsOf: [snapshot.session, snapshot.opus, snapshot.sonnet, snapshot.design, snapshot.fable])
        }
        for providerSnapshot in providerSnapshots where providerSnapshot.provider != .claude {
            windows.append(contentsOf: providerSnapshot.windows.map { $0 })
        }
        return overallStatus(from: windows, asOf: now)
    }
}
