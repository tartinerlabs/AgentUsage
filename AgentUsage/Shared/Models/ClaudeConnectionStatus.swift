//
//  ClaudeConnectionStatus.swift
//  AgentUsage
//
//  A clear, user-facing summary of the app's connection to Claude's usage API.
//  Derived from credential validity, last-fetch success, network reachability,
//  and service outages so macOS and iOS/iPadOS present connection health
//  identically.
//

import SwiftUI

/// The app's connection state to Claude's usage endpoint.
enum ClaudeConnectionStatus: Equatable, Sendable {
    /// Live usage was fetched successfully during this session.
    case connected
    /// Authenticated, but the data on screen came from the cache after a failed
    /// online refresh.
    case cached
    /// The device has no network connection.
    case offline
    /// Authenticated and reachable, but Claude reports no usage yet (windows reset).
    case noUsageData
    /// Claude's usage service is returning errors (HTTP 5xx / unavailable).
    case serviceUnavailable
    /// A fetch is in progress and there is nothing cached to show yet.
    case checking
    /// Not connected — credentials are missing/invalid, or another error occurred.
    case disconnected(message: String?)
}

extension ClaudeConnectionStatus {
    /// Short headline, e.g. "Connected".
    var title: String {
        switch self {
        case .connected, .noUsageData: "Connected"
        case .cached: "Showing cached data"
        case .offline: "Offline"
        case .serviceUnavailable: "Claude unavailable"
        case .checking: "Checking…"
        case .disconnected: "Not connected"
        }
    }

    /// SF Symbol used when the status is not in progress.
    var systemImage: String {
        switch self {
        case .connected, .noUsageData: "checkmark.circle.fill"
        case .cached: "clock.arrow.circlepath"
        case .offline: "wifi.slash"
        case .serviceUnavailable: "exclamationmark.triangle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .disconnected: "xmark.circle.fill"
        }
    }

    /// System-semantic status color (see DESIGN.md): green on-track, orange
    /// warning, red critical.
    var tint: Color {
        switch self {
        case .connected, .noUsageData: .green
        case .cached, .offline, .serviceUnavailable: .orange
        case .checking: .secondary
        case .disconnected: .red
        }
    }

    /// Whether a spinner should replace the icon.
    var isInProgress: Bool {
        if case .checking = self { return true }
        return false
    }

    /// Whether the app currently has a working connection to Claude (fresh or cached).
    var isConnected: Bool {
        switch self {
        case .connected, .cached, .noUsageData: true
        case .offline, .serviceUnavailable, .checking, .disconnected: false
        }
    }
}
