//
//  UsageActivitySelection.swift
//  AgentUsageKit
//
//  Stable provider/window identity for widgets and Live Activities.
//

/// Identifies the exact provider rate window tracked by a widget or Live Activity.
///
/// The provider is part of the identity because different providers may use the
/// same window identifier (for example, `session`).
public struct UsageActivitySelection: Sendable, Codable, Hashable {
    public let provider: Provider
    public let windowID: UsageWindowID

    public init(provider: Provider, windowID: UsageWindowID) {
        self.provider = provider
        self.windowID = windowID
    }
}
