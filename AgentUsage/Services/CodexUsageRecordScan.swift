//
//  CodexUsageRecordScan.swift
//  AgentUsage
//
//  Session token totals from Codex's `token_usage_record` rollout lines.
//

#if os(macOS)
import Foundation

/// Reverse-scan state for a Codex rollout's running token totals.
///
/// Newer Codex appends a `token_usage_record` after every completed response. Its
/// `thread_token_usage` adds up every billed response, including remote compaction,
/// whose usage never reaches the `token_count` total, and a context-window overflow
/// leaves it alone while it empties that total. When a rollout has records, the newest
/// one is the session total. Otherwise the `token_count` totals are the fallback, summed
/// across context-window resets by `CodexTokenTotalScan`.
///
/// Codex writes each record just before the `token_count` for the same response, so
/// the newest record sits between the newest billed `token_count` and the
/// `turn_context` that started its turn. Rollouts from older Codex have no records, so
/// the scan stops looking at that `turn_context`.
nonisolated struct CodexUsageRecordScan {
    /// Newest `token_count` `info.total_token_usage`: the running total a fork inherits.
    private(set) var tokenCountTotal: CodexCumulativeTokenUsage?
    private var tokenCountSegments = CodexTokenTotalScan()
    /// Newest `token_usage_record` `thread_token_usage`.
    private(set) var recordTotal: CodexCumulativeTokenUsage?
    private var sawBilledUsage = false
    private var passedBilledTurn = false

    var isComplete: Bool {
        if recordTotal != nil {
            return tokenCountTotal != nil || passedBilledTurn
        }
        return tokenCountTotal != nil && passedBilledTurn && tokenCountSegments.isComplete
    }

    /// Whether the next `turn_context` ends the search for a record.
    var needsTurnBoundary: Bool {
        !isComplete && sawBilledUsage
    }

    /// The session's own usage. A fork or a reverted thread's rollout starts both running
    /// totals from its source's, which the source's rollout already counts.
    func sessionTotal(
        inheritedTokenCount: CodexCumulativeTokenUsage?,
        inheritedRecord: CodexCumulativeTokenUsage?
    ) -> CodexCumulativeTokenUsage? {
        let tokenCount = tokenCountSegments.sessionTotal(excluding: inheritedTokenCount)
        guard let recordTotal else { return tokenCount }
        let record = inheritedRecord.map { recordTotal.excluding(inherited: $0) } ?? recordTotal
        // When Codex resumes a rollout written before it kept records, its records start
        // at zero while `token_count` carries on from the earlier total.
        if let tokenCount, Self.billedTokens(tokenCount) > Self.billedTokens(record) {
            return tokenCount
        }
        return record
    }

    /// Feeds one `token_count` event's `info.total_token_usage`, with its
    /// `info.last_token_usage.total_tokens` if present. Lines must arrive newest first.
    mutating func recordTokenCount(_ total: CodexCumulativeTokenUsage, lastTotalTokens: Int? = nil) {
        if tokenCountTotal == nil {
            tokenCountTotal = total
        }
        tokenCountSegments.record(total, lastTotalTokens: lastTotalTokens)
        // An empty total is a context-window reset, which is not a response.
        if Self.billedTokens(total) > 0 {
            sawBilledUsage = true
        }
    }

    /// Feeds one `token_usage_record`'s `thread_token_usage`. Lines must arrive newest first.
    mutating func recordUsageRecord(_ threadTotal: CodexCumulativeTokenUsage) {
        if recordTotal == nil {
            recordTotal = threadTotal
        }
        sawBilledUsage = true
    }

    /// Feeds one `turn_context`. Lines must arrive newest first.
    mutating func recordTurnContext() {
        if sawBilledUsage {
            passedBilledTurn = true
        }
    }

    /// Codex's input includes cached input and its output includes reasoning.
    private static func billedTokens(_ usage: CodexCumulativeTokenUsage) -> Int {
        usage.inputTokens + usage.outputTokens
    }
}
#endif
