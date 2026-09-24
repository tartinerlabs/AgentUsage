//
//  StaticUsageLogSource.swift
//  AgentUsageTests
//
//  A local log source that returns fixed entries, for aggregation tests
//

import Foundation
@testable import AgentUsage
import AgentUsageKit

/// Returns the given entries at or after `since`, and counts how often it was read.
actor StaticUsageLogSource: UsageLogSource {
    nonisolated let provider: Provider
    private let entries: [ProviderUsageEntry]

    /// Number of `fetchEntries(since:)` calls, to prove a source was or was not read.
    private(set) var fetchCount = 0

    init(provider: Provider = .openCode, entries: [ProviderUsageEntry]) {
        self.provider = provider
        self.entries = entries
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        fetchCount += 1
        return entries.filter { $0.timestamp >= since }
    }
}
