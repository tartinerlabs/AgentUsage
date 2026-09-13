//
//  ProviderStatus.swift
//  AgentUsage
//
//  Per-provider freshness of the usage shown on a provider card, so a rate limit,
//  outage, or failed fetch for one provider never reads as app-wide.
//

import SwiftUI
import AgentUsageKit

enum ProviderStatus: Equatable, Sendable {
    /// The last fetch succeeded and the data is current.
    case fresh
    /// The data on screen is older than a normal refresh would leave it.
    case cached
    /// The device has no network connection.
    case offline
    /// The provider returned HTTP 429; automatic refresh resumes after `until`.
    case rateLimited(until: Date)
    /// The provider's service is returning server errors.
    case serviceDown
    /// The last fetch failed for another reason (auth, invalid response, network).
    case failed(message: String)
}

extension ProviderStatus {
    var title: String {
        switch self {
        case .fresh: "Up to date"
        case .cached: "Cached"
        case .offline: "Offline"
        case .rateLimited: "Rate limited"
        case .serviceDown: "Service down"
        case .failed: "Update failed"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh: "checkmark.circle.fill"
        case .cached: "clock.arrow.circlepath"
        case .offline: "wifi.slash"
        case .rateLimited: "hourglass"
        case .serviceDown: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    /// Severity expressed as `UsageStatus` so colors stay centralized (see DESIGN.md).
    var severity: UsageStatus {
        switch self {
        case .fresh: .onTrack
        case .cached, .offline, .rateLimited: .warning
        case .serviceDown, .failed: .critical
        }
    }

    /// Why the data isn't fresh, followed by how old the shown data is when known.
    func detail(fetchedAt: Date?, now: Date) -> String {
        let reason: String = switch self {
        case .fresh: ""
        case .cached: "Waiting for a newer update."
        case .offline: "No internet connection."
        case .rateLimited(let until):
            "Automatic refresh resumes \(Self.relativeFormatter.localizedString(for: until, relativeTo: now))."
        case .serviceDown: "The service returned a server error."
        case .failed(let message): message
        }
        let age = fetchedAt.map { "Last updated \(DateFormatters.relativeDescription(from: $0, to: now))." }
        return [reason, age].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
