//
//  OutageIncident.swift
//  ClaudeMeterKit
//

import Foundation

/// A tracked service outage for a single provider.
///
/// Created when a provider's usage fetch fails with an outage-class error
/// (HTTP 5xx / service unavailable) and cleared on the next successful fetch.
/// `startedAt` is preserved across repeated failures so the UI can show how long
/// the provider has been down; `lastErrorCode` reflects the most recent failure.
public struct OutageIncident: Equatable, Sendable, Codable {
    /// When the outage was first observed (preserved across repeated failures).
    public let startedAt: Date

    /// HTTP status of the most recent failure (e.g. 503), if known.
    public var lastErrorCode: Int?

    public init(startedAt: Date, lastErrorCode: Int?) {
        self.startedAt = startedAt
        self.lastErrorCode = lastErrorCode
    }
}
