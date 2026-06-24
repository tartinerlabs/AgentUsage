//
//  CodexLogSource.swift
//  ClaudeMeter
//
//  Token/cost usage from OpenAI Codex CLI rollout logs.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog

/// Reads Codex CLI session rollout logs (`~/.codex/sessions/<y>/<m>/<d>/rollout-*.jsonl`
/// and `archived_sessions/`).
///
/// Each rollout file is one session. Token usage lives in `event_msg` payloads of
/// type `token_count`. We emit one entry **per turn** (per `token_count` event),
/// preferring `info.last_token_usage` and otherwise differencing
/// `info.total_token_usage` against the previous cumulative total. Per-turn entries
/// keep each turn on its own timestamp so day/30-day buckets stay accurate even when
/// a session spans midnight. Each turn is attributed to the most recent
/// `turn_context.model` seen before it.
actor CodexLogSource: UsageLogSource {
    nonisolated let provider: Provider = .codex

    private let fileManager = FileManager.default
    private let directories: [URL]

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(directories: [URL] = Constants.codexSessionsDirectories) {
        self.directories = directories
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        let files = rolloutFiles(modifiedAfter: since)
        var entries: [ProviderUsageEntry] = []
        for file in files {
            entries.append(contentsOf: parseRollout(at: file).filter { $0.timestamp >= since })
        }
        return entries
    }

    /// Cumulative or per-turn Codex token totals from a `token_count` event.
    private struct CodexUsageTotals {
        var input = 0
        var cachedInput = 0
        var output = 0
        var reasoning = 0

        static let zero = CodexUsageTotals()

        init() {}

        init(_ dict: [String: Any]) {
            input = dict["input_tokens"] as? Int ?? 0
            cachedInput = dict["cached_input_tokens"] as? Int ?? 0
            output = dict["output_tokens"] as? Int ?? 0
            reasoning = dict["reasoning_output_tokens"] as? Int ?? 0
        }

        /// Per-turn delta = this cumulative total minus the previous one (saturating).
        func subtracting(_ other: CodexUsageTotals) -> CodexUsageTotals {
            var result = CodexUsageTotals()
            result.input = max(0, input - other.input)
            result.cachedInput = max(0, cachedInput - other.cachedInput)
            result.output = max(0, output - other.output)
            result.reasoning = max(0, reasoning - other.reasoning)
            return result
        }

        /// Split into disjoint components so totals/cost don't double-count:
        /// `input` includes cached; `output` includes reasoning.
        var tokenCount: TokenCount {
            TokenCount(
                inputTokens: max(0, input - cachedInput),
                outputTokens: max(0, output - reasoning),
                cacheCreationTokens: 0,
                cacheReadTokens: cachedInput,
                reasoningTokens: reasoning
            )
        }
    }

    // MARK: - File discovery

    private func rolloutFiles(modifiedAfter cutoff: Date) -> [URL] {
        var result: [URL] = []
        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-") else { continue }
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if modDate >= cutoff {
                    result.append(url)
                }
            }
        }
        return result
    }

    // MARK: - Parsing

    private func parseRollout(at url: URL) -> [ProviderUsageEntry] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [] }

        let fileModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        var sessionId: String?
        var currentModel: String?
        var previousTotal: CodexUsageTotals = .zero
        var entries: [ProviderUsageEntry] = []
        var turnIndex = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            let payload = json["payload"] as? [String: Any]

            switch type {
            case "session_meta":
                sessionId = payload?["id"] as? String
            case "turn_context":
                if let m = payload?["model"] as? String, !m.isEmpty { currentModel = m }
            case "event_msg":
                guard (payload?["type"] as? String) == "token_count",
                      let info = payload?["info"] as? [String: Any] else { continue }

                // Prefer the per-turn figure; else difference the cumulative total.
                let turnTotals: CodexUsageTotals
                if let last = info["last_token_usage"] as? [String: Any] {
                    turnTotals = CodexUsageTotals(last)
                } else if let total = info["total_token_usage"] as? [String: Any] {
                    let totals = CodexUsageTotals(total)
                    turnTotals = totals.subtracting(previousTotal)
                } else {
                    continue
                }

                // Keep the cumulative baseline current for the next delta.
                if let total = info["total_token_usage"] as? [String: Any] {
                    previousTotal = CodexUsageTotals(total)
                }

                let tokens = turnTotals.tokenCount
                guard tokens.totalTokens > 0 else { continue }

                let timestamp = (json["timestamp"] as? String).flatMap {
                    isoFormatter.date(from: $0) ?? isoFormatterNoFraction.date(from: $0)
                } ?? fileModified ?? Date()

                let id = sessionId ?? url.deletingPathExtension().lastPathComponent
                entries.append(
                    ProviderUsageEntry(
                        provider: .codex,
                        model: currentModel ?? "gpt-5-codex",
                        pricingProviderKey: "openai",
                        tokens: tokens,
                        timestamp: timestamp,
                        dedupKey: "codex:\(id):\(turnIndex)"
                    )
                )
                turnIndex += 1
            default:
                continue
            }
        }

        return entries
    }
}
#endif
