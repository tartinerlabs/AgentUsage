//
//  CodexCumulativeTokenUsage.swift
//  AgentUsage
//
//  Cumulative token totals from Codex `token_count` records.
//

#if os(macOS)
import Foundation

/// One `token_count` event's cumulative `info.total_token_usage`.
nonisolated struct CodexCumulativeTokenUsage: Equatable, Sendable {
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var reasoningOutputTokens = 0
    /// Reported `total_tokens`: input plus output, plus the context window size after a
    /// reset. Not priced; only used to tell resets apart.
    var totalTokens = 0

    init() {}

    init(_ usage: [String: Any]) {
        inputTokens = usage["input_tokens"] as? Int ?? 0
        cachedInputTokens = usage["cached_input_tokens"] as? Int ?? 0
        outputTokens = usage["output_tokens"] as? Int ?? 0
        reasoningOutputTokens = usage["reasoning_output_tokens"] as? Int ?? 0
        totalTokens = usage["total_tokens"] as? Int ?? 0
    }

    /// No priced counter is set. Codex writes this when a request overflows the
    /// model context window, as an imported session's baseline, and before a
    /// session's first billed response.
    var isEmpty: Bool {
        inputTokens == 0 && cachedInputTokens == 0
            && outputTokens == 0 && reasoningOutputTokens == 0
    }

    /// Codex's `total_tokens` is input plus output. A total above that grew from a
    /// baseline with no priced usage: a context-window reset (`total_tokens` set to
    /// the window size) or an imported session (`total_tokens` only). An earlier
    /// segment may hold more usage, so the scan has to find that baseline.
    var followsEmptyBaseline: Bool {
        unpricedTokens > 0
    }

    mutating func add(_ other: CodexCumulativeTokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }

    /// The usage recorded on top of `inherited`, the running total that a fork or a
    /// reverted thread's rollout starts from. Codex adds each response to that total, so
    /// later totals include it until a context-window reset replaces the running total
    /// with an empty one. Totals after a reset are returned unchanged.
    func excluding(inherited: CodexCumulativeTokenUsage) -> CodexCumulativeTokenUsage {
        guard includes(inherited) else { return self }
        var usage = self
        usage.inputTokens -= inherited.inputTokens
        usage.cachedInputTokens -= inherited.cachedInputTokens
        usage.outputTokens -= inherited.outputTokens
        usage.reasoningOutputTokens -= inherited.reasoningOutputTokens
        usage.totalTokens -= inherited.totalTokens
        return usage
    }

    /// Adding a response grows `total_tokens` by exactly its input plus output, so the
    /// unpriced part of `total_tokens` stays the same until a reset sets it to the window
    /// size and every priced counter back to zero.
    private func includes(_ inherited: CodexCumulativeTokenUsage) -> Bool {
        unpricedTokens == inherited.unpricedTokens
            && inputTokens >= inherited.inputTokens
            && cachedInputTokens >= inherited.cachedInputTokens
            && outputTokens >= inherited.outputTokens
            && reasoningOutputTokens >= inherited.reasoningOutputTokens
    }

    private var unpricedTokens: Int {
        totalTokens - inputTokens - outputTokens
    }
}
#endif
