//
//  TokenLogEntry.swift
//  AgentUsage
//

import Foundation
import AgentUsageKit
import SwiftData

/// Persisted token usage entry from Claude Code JSONL logs
@Model
final class TokenLogEntry {

    /// Every aggregation query filters on `timestamp >= startDate`. Without this index those fetches
    /// full-scan the table (`SCAN ZTOKENLOGENTRY`); at ~77k rows SQLite's sorter spilled to disk
    /// and the app exceeded macOS's 2 GB/24h disk-writes limit (reported, not killed).
    #Index<TokenLogEntry>([\.timestamp])

    /// Unique identifier: messageId:requestId composite
    @Attribute(.unique) var id: String

    /// Original message ID from the log
    var messageId: String

    /// Original request ID from the log
    var requestId: String

    /// Model name (e.g., "claude-opus-4-5-20250514")
    var modelName: String

    /// Claude session identifier. Nil or empty for legacy rows imported before
    /// session metadata was captured. This stays optional so rows written by an
    /// older app binary after a lightweight migration remain materializable.
    var sessionID: String? = nil

    /// Normalized effort-level value. Optional for logs and migrated rows that do not expose it.
    var effortLevelRaw: String? = nil

    /// True for entries imported from Claude subagent session files. Nil is the
    /// migration-safe legacy representation and is treated as false by readers.
    var isSubagentSession: Bool? = nil

    /// Token counts
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL (billed at 2× input). Default 0 for
    /// rows imported before this field existed (lightweight SwiftData migration).
    var cacheCreation1hTokens: Int = 0

    /// Timestamp from the log entry. The `hashModifier` changes the entity's version hash so
    /// `TokenUsageMigrationPlan` actually migrates existing stores and adds the index above —
    /// an index alone leaves the hash unchanged. Don't remove or rename it.
    @Attribute(hashModifier: "timestamp-indexed") var timestamp: Date

    /// Cost in USD calculated at import time
    var costUSD: Double

    /// Whether the request was served in fast mode (premium pricing). Default false for migrated rows.
    var isFastMode: Bool = false

    init(
        messageId: String,
        requestId: String,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        timestamp: Date,
        costUSD: Double,
        sessionID: String? = nil,
        effortLevelRaw: String? = nil,
        isSubagentSession: Bool? = nil,
        cacheCreation1hTokens: Int = 0,
        isFastMode: Bool = false
    ) {
        self.id = "\(messageId):\(requestId)"
        self.messageId = messageId
        self.requestId = requestId
        self.modelName = modelName
        self.sessionID = sessionID
        self.effortLevelRaw = effortLevelRaw
        self.isSubagentSession = isSubagentSession
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.timestamp = timestamp
        self.costUSD = costUSD
        self.isFastMode = isFastMode
    }

    var effortLevel: EffortLevel? {
        effortLevelRaw.map(EffortLevel.init(rawValue:))
    }

    /// Total tokens for this entry
    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Convert to TokenCount for aggregation
    var tokenCount: TokenCount {
        TokenCount(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreation1hTokens: cacheCreation1hTokens
        )
    }
}

// MARK: - Schema versions

/// Store schema before `TokenLogEntry` gained its timestamp index. Kept only so the
/// migration plan can recognise existing stores; do not use these types directly.
nonisolated enum TokenUsageSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TokenLogEntry.self, ImportedFile.self, DailyUsageRecordEntity.self, ProviderWindowDailyPeakEntity.self]
    }

    @Model
    final class TokenLogEntry {
        @Attribute(.unique) var id: String
        var messageId: String
        var requestId: String
        var modelName: String
        var sessionID: String? = nil
        var effortLevelRaw: String? = nil
        var isSubagentSession: Bool? = nil
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var cacheCreation1hTokens: Int = 0
        var timestamp: Date
        var costUSD: Double
        var isFastMode: Bool = false

        init(
            messageId: String,
            requestId: String,
            modelName: String,
            inputTokens: Int,
            outputTokens: Int,
            cacheCreationTokens: Int,
            cacheReadTokens: Int,
            timestamp: Date,
            costUSD: Double
        ) {
            self.id = "\(messageId):\(requestId)"
            self.messageId = messageId
            self.requestId = requestId
            self.modelName = modelName
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheCreationTokens = cacheCreationTokens
            self.cacheReadTokens = cacheReadTokens
            self.timestamp = timestamp
            self.costUSD = costUSD
        }
    }
}

/// Current store schema: `TokenLogEntry` with `#Index` on `timestamp`.
nonisolated enum TokenUsageSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TokenLogEntry.self, ImportedFile.self, DailyUsageRecordEntity.self, ProviderWindowDailyPeakEntity.self]
    }
}

/// Adds the `timestamp` index to existing stores. An index doesn't change the version hash,
/// so neither an unversioned container nor this stage alone migrates them; the stage only runs
/// because of the `hashModifier` on `TokenLogEntry.timestamp`. Verified against a copy of a
/// 77k-row store: rows and integrity preserved, index created, second open is a no-op.
nonisolated enum TokenUsageMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TokenUsageSchemaV1.self, TokenUsageSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TokenUsageSchemaV1.self, toVersion: TokenUsageSchemaV2.self)]
    }
}
