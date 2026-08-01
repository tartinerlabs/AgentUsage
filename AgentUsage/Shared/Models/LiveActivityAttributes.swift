//
//  LiveActivityAttributes.swift
//  AgentUsage
//
//  Shared Live Activity types for both main app and widget extension
//

#if os(iOS)
import ActivityKit
import AgentUsageKit
import Foundation

// MARK: - Live Activity Attributes

/// Whether the selected window can currently show trustworthy usage values.
nonisolated enum UsageActivityAvailability: String, Codable, Hashable, Sendable {
    case available
    case awaitingRefresh
    case unavailable
}

/// Attributes for an Agent Usage Live Activity.
///
/// `selectedMetric` remains the sole fixed property so activities created by
/// older versions continue to decode. Provider/window identity lives in the
/// dynamic state, which also lets an existing activity switch selections.
/// `nonisolated` so ActivityKit, which consumes this conformance from its own
/// concurrent contexts, is not blocked by the project's MainActor default isolation.
nonisolated struct AgentUsageLiveActivityAttributes: ActivityAttributes {
    /// Fixed legacy display-name fallback set when the activity starts.
    var selectedMetric: String

    /// Dynamic properties updated over time
    public struct ContentState: Codable, Hashable {
        var percentUsed: Int
        var timeUntilReset: String
        var statusRaw: String  // "onTrack", "warning", "critical"

        /// Provider-neutral fields added after the initial Claude-only schema.
        /// They must remain optional so existing activities decode after upgrade.
        var selection: UsageActivitySelection?
        var windowDisplayName: String?
        var resetsAt: Date?
        var fetchedAt: Date?
        var availabilityRaw: String?

        var status: UsageStatus {
            UsageStatus(rawValue: statusRaw) ?? .onTrack
        }

        var availability: UsageActivityAvailability {
            guard let availabilityRaw else { return .available }
            return UsageActivityAvailability(rawValue: availabilityRaw) ?? .unavailable
        }

        var provider: AgentUsageKit.Provider {
            selection?.provider ?? .claude
        }

        /// Only the visual progress is clamped. The percentage label can still
        /// communicate legitimate over-limit usage above 100%.
        var normalizedProgress: Double {
            min(max(Double(percentUsed) / 100, 0), 1)
        }

        /// Legacy Claude-only state construction.
        init(from window: UsageWindow) {
            self.percentUsed = window.percentUsed
            self.timeUntilReset = window.timeUntilReset
            self.statusRaw = window.status.rawValue
            self.selection = nil
            self.windowDisplayName = nil
            self.resetsAt = nil
            self.fetchedAt = nil
            self.availabilityRaw = nil
        }

        init(
            percentUsed: Int,
            timeUntilReset: String,
            statusRaw: String,
            selection: UsageActivitySelection? = nil,
            windowDisplayName: String? = nil,
            resetsAt: Date? = nil,
            fetchedAt: Date? = nil,
            availabilityRaw: String? = nil
        ) {
            self.percentUsed = percentUsed
            self.timeUntilReset = timeUntilReset
            self.statusRaw = statusRaw
            self.selection = selection
            self.windowDisplayName = windowDisplayName
            self.resetsAt = resetsAt
            self.fetchedAt = fetchedAt
            self.availabilityRaw = availabilityRaw
        }

        init(
            selection: UsageActivitySelection,
            window: UsageWindow,
            fetchedAt: Date,
            availability: UsageActivityAvailability = .available
        ) {
            self.init(
                percentUsed: window.percentUsed,
                timeUntilReset: window.timeUntilReset,
                statusRaw: window.status.rawValue,
                selection: selection,
                windowDisplayName: window.displayName,
                resetsAt: window.resetsAt,
                fetchedAt: fetchedAt,
                availabilityRaw: availability.rawValue
            )
        }
    }
}
#endif
