//
//  CodexTokenTotalScan.swift
//  AgentUsage
//
//  Session token totals from Codex's cumulative `token_count` records.
//

#if os(macOS)
import Foundation

/// Reverse-scan state for a session's cumulative `token_count` totals.
///
/// Codex appends a cumulative total after each response, so the newest one is
/// normally the whole session. When a request overflows the model context window,
/// Codex replaces that total with an empty one (`total_tokens` = window size) and
/// later responses accumulate from there. Each reset closes a segment; the session
/// total is the sum of every segment's newest non-empty total. Reading stops at a
/// segment total that did not grow from an empty baseline, or at an empty total
/// with no usage before it.
nonisolated struct CodexTokenTotalScan: Sendable {
    /// Summed totals of every segment newer than `oldestSegment`.
    private var newerSegments: CodexCumulativeTokenUsage?
    /// The oldest segment read, the only one that can continue an inherited total.
    private var oldestSegment: CodexCumulativeTokenUsage?
    private var sawEmptyTotal = false
    private var needsSegmentTotal = true
    private var needsSegmentBaseline = false

    var isComplete: Bool {
        !needsSegmentTotal && !needsSegmentBaseline
    }

    /// The summed session total, or an empty total when Codex only recorded empty ones.
    ///
    /// - Parameter inherited: The running total a fork or a reverted thread's rollout
    ///   started from, left out of the oldest segment when that segment continues it.
    func sessionTotal(excluding inherited: CodexCumulativeTokenUsage? = nil) -> CodexCumulativeTokenUsage? {
        guard let oldestSegment else {
            return sawEmptyTotal ? CodexCumulativeTokenUsage() : nil
        }
        var total = inherited.map { oldestSegment.excluding(inherited: $0) } ?? oldestSegment
        if let newerSegments {
            total.add(newerSegments)
        }
        return total
    }

    /// Feeds one `token_count` record. Records must arrive newest first.
    ///
    /// - Parameters:
    ///   - usage: The record's cumulative `info.total_token_usage`.
    ///   - lastTotalTokens: The record's `info.last_token_usage.total_tokens`, if present.
    mutating func record(_ usage: CodexCumulativeTokenUsage, lastTotalTokens: Int?) {
        if usage.isEmpty {
            guard needsSegmentTotal || needsSegmentBaseline else { return }
            sawEmptyTotal = true
            // An empty total is a baseline, or a compaction record after one that only
            // re-estimated `last_token_usage`. The next non-empty total belongs to an
            // earlier segment, unless this record shows no usage came before it.
            needsSegmentBaseline = false
            needsSegmentTotal = !Self.hasNoEarlierUsage(usage, lastTotalTokens: lastTotalTokens)
        } else if needsSegmentTotal {
            if let oldestSegment {
                var combined = newerSegments ?? CodexCumulativeTokenUsage()
                combined.add(oldestSegment)
                newerSegments = combined
            }
            oldestSegment = usage
            needsSegmentTotal = false
            needsSegmentBaseline = usage.followsEmptyBaseline
        }
    }

    /// An empty total that its own `last_token_usage` fully accounts for has no usage
    /// before it. Codex writes one when a session's first request overflows (`last`
    /// is the window size minus the previous total) and as the baseline of an
    /// imported session (`last` equals the total).
    private static func hasNoEarlierUsage(
        _ usage: CodexCumulativeTokenUsage,
        lastTotalTokens: Int?
    ) -> Bool {
        usage.totalTokens > 0 && lastTotalTokens == usage.totalTokens
    }
}
#endif
