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

/// Reads Codex CLI session rollout logs (`~/.codex/sessions/<y>/<m>/<d>/rollout-*.jsonl`).
///
/// Each rollout file is one session. Token usage lives in `event_msg` payloads of
/// type `token_count` (`info.total_token_usage`, cumulative for the session). We
/// take the last such event per file and emit a single entry, attributed to the
/// session's most recent `turn_context.model`.
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
            if let entry = parseRollout(at: file), entry.timestamp >= since {
                entries.append(entry)
            }
        }
        return entries
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

    private func parseRollout(at url: URL) -> ProviderUsageEntry? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var sessionId: String?
        var model: String?
        var lastTokenUsage: [String: Any]?
        var lastTimestamp: Date?

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            let payload = json["payload"] as? [String: Any]

            switch type {
            case "session_meta":
                sessionId = payload?["id"] as? String
            case "turn_context":
                if let m = payload?["model"] as? String, !m.isEmpty { model = m }
            case "event_msg":
                guard (payload?["type"] as? String) == "token_count",
                      let info = payload?["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any] else { continue }
                lastTokenUsage = total
                if let ts = json["timestamp"] as? String {
                    lastTimestamp = isoFormatter.date(from: ts) ?? isoFormatterNoFraction.date(from: ts)
                }
            default:
                continue
            }
        }

        guard let total = lastTokenUsage else { return nil }

        // Codex: total = input + output; `input` includes cached, `output` includes reasoning.
        // Split into disjoint components so totals/cost don't double-count.
        let rawInput = total["input_tokens"] as? Int ?? 0
        let cachedInput = total["cached_input_tokens"] as? Int ?? 0
        let rawOutput = total["output_tokens"] as? Int ?? 0
        let reasoning = total["reasoning_output_tokens"] as? Int ?? 0

        let tokens = TokenCount(
            inputTokens: max(0, rawInput - cachedInput),
            outputTokens: max(0, rawOutput - reasoning),
            cacheCreationTokens: 0,
            cacheReadTokens: cachedInput,
            reasoningTokens: reasoning
        )

        let id = sessionId ?? url.deletingPathExtension().lastPathComponent
        let timestamp = lastTimestamp
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()

        return ProviderUsageEntry(
            provider: .codex,
            model: model ?? "gpt-5-codex",
            pricingProviderKey: "openai",
            tokens: tokens,
            timestamp: timestamp,
            dedupKey: "codex:\(id)"
        )
    }
}
#endif
