//
//  AppConnectionStatus.swift
//  AgentUsage
//

import SwiftUI

enum ContinuityNodeState: Equatable, Sendable {
    case connected(lastSeenAt: Date?)
    case waiting(lastSeenAt: Date?)
    case unavailable
    case checking
    case revoked
}

struct ContinuityNetworkStatus: Equatable, Sendable {
    let mac: ContinuityNodeState
    let iPhone: ContinuityNodeState
    let iPad: ContinuityNodeState
}

/// Provider-neutral status for the connection between AgentUsage installs.
enum AppConnectionStatus: Equatable, Sendable {
    case linked(lastUpdatedText: String?)
    case syncedFromMac(lastUpdatedText: String?)
    case waitingForDevices(message: String?)
    case checking
    case waitingForMac
    case revoked
    case needsSetup(message: String?)
}

extension AppConnectionStatus {
    var title: String {
        switch self {
        case .linked:
            #if os(macOS)
            return "Continuity Sync is on"
            #else
            return "Continuity Sync is on"
            #endif
        case .syncedFromMac:
            return "Updated from your Mac"
        case .waitingForDevices:
            return "Waiting for iPhone or iPad"
        case .checking:
            return "Checking Continuity Sync"
        case .waitingForMac:
            return "Waiting for your Mac"
        case .revoked:
            return "Continuity Sync is off"
        case .needsSetup:
            #if os(macOS)
            return "Not sharing yet"
            #else
            return "Open \(Constants.appDisplayName) on Mac"
            #endif
        }
    }

    var systemImage: String {
        switch self {
        case .linked, .syncedFromMac:
            return "iphone.and.arrow.forward.inward"
        case .waitingForDevices:
            return "laptopcomputer.and.iphone"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .waitingForMac:
            return "laptopcomputer.and.iphone"
        case .revoked:
            return "link.badge.minus"
        case .needsSetup:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .linked, .syncedFromMac:
            return .green
        case .checking:
            return .secondary
        case .waitingForDevices, .waitingForMac, .revoked, .needsSetup:
            return .orange
        }
    }

    var isInProgress: Bool {
        if case .checking = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .linked(let lastUpdatedText):
            #if os(macOS)
            return lastUpdatedText.map { "This Mac shared the latest usage. Last updated \($0)." }
                ?? "This Mac keeps your iPhone and iPad up to date through iCloud."
            #else
            return lastUpdatedText.map { "Your Mac shared the latest usage. Last updated \($0)." }
                ?? "Your Mac keeps this device up to date through iCloud."
            #endif
        case .syncedFromMac(let lastUpdatedText):
            return lastUpdatedText.map { "Your Mac shared the latest usage. Last updated \($0)." }
                ?? "Your Mac shared the latest usage."
        case .waitingForDevices(let message):
            return message
                ?? "This Mac shared the latest usage. Open Agent Usage on iPhone or iPad to verify the connection."
        case .checking:
            return "Looking for the latest update from your Mac."
        case .waitingForMac:
            return "Open \(Constants.appDisplayName) on your Mac to share the latest usage."
        case .revoked:
            #if os(macOS)
            return "This Mac will not share updates until Continuity Sync is resumed."
            #else
            return "This device will not receive updates until Continuity Sync is resumed."
            #endif
        case .needsSetup(let message):
            if let message, !message.isEmpty {
                return message
            }
            #if os(macOS)
            return "Open \(Constants.appDisplayName) on this Mac once so your other devices can stay up to date."
            #else
            return "Open \(Constants.appDisplayName) on your Mac first so this device can stay up to date."
            #endif
        }
    }
}
