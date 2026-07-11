//
//  TokenLogEntry.swift
//  AgentUsage
//

import Foundation
import SwiftData

/// Persisted token usage entry from Claude Code JSONL logs
@Model
final class TokenLogEntry {

    /// Unique identifier: messageId:requestId composite
    @Attribute(.unique) var id: String

    /// Original message ID from the log
    var messageId: String

    /// Original request ID from the log
    var requestId: String

    /// Model name (e.g., "claude-opus-4-5-20250514")
    var modelName: String

    /// Token counts
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    /// Subset of `cacheCreationTokens` written with a 1-hour TTL (billed at 2× input). Default 0 for
    /// rows imported before this field existed (lightweight SwiftData migration).
    var cacheCreation1hTokens: Int = 0

    /// Timestamp from the log entry
    var timestamp: Date

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
        cacheCreation1hTokens: Int = 0,
        isFastMode: Bool = false
    ) {
        self.id = "\(messageId):\(requestId)"
        self.messageId = messageId
        self.requestId = requestId
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.timestamp = timestamp
        self.costUSD = costUSD
        self.isFastMode = isFastMode
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

