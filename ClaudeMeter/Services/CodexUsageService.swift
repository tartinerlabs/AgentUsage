//
//  CodexUsageService.swift
//  ClaudeMeter
//
//  Codex CLI rate-limit windows from rollout logs.
//

#if os(macOS)
import Foundation
import ClaudeMeterKit
import OSLog

/// Reads the current Codex rate-limit windows from the most recent rollout log.
///
/// Codex emits these in `event_msg`/`token_count` payloads under `rate_limits`:
/// `primary` (`window_minutes:300`, 5h) and `secondary` (`window_minutes:10080`, 7d),
/// each with `used_percent` and `resets_at`. There is no network call.
actor CodexUsageService {
    nonisolated let provider: Provider = .codex

    private let fileManager = FileManager.default
    private let directories: [URL]

    init(directories: [URL] = Constants.codexSessionsDirectories) {
        self.directories = directories
    }

    /// Returns the current Codex windows, or nil if no rate-limit data is available.
    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        guard let newest = newestRolloutFile() else { return nil }
        return parseRateLimits(at: newest)
    }

    // MARK: - File discovery

    private func newestRolloutFile() -> URL? {
        var best: (url: URL, date: Date)?
        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-") else { continue }
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || modDate > best!.date {
                    best = (url, modDate)
                }
            }
        }
        return best?.url
    }

    // MARK: - Parsing

    private func parseRateLimits(at url: URL) -> ProviderUsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var lastRateLimits: [String: Any]?
        var planType: String?

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (json["type"] as? String) == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }
            lastRateLimits = rateLimits
            planType = (rateLimits["plan_type"] as? String) ?? planType
        }

        guard let rateLimits = lastRateLimits else { return nil }

        var windows: [UsageWindow] = []
        if let primary = window(from: rateLimits["primary"], type: .codexFiveHour) {
            windows.append(primary)
        }
        if let secondary = window(from: rateLimits["secondary"], type: .codexWeekly) {
            windows.append(secondary)
        }
        guard !windows.isEmpty else { return nil }

        return ProviderUsageSnapshot(
            provider: .codex,
            windows: windows,
            planName: planType,
            fetchedAt: Date()
        )
    }

    private func window(from raw: Any?, type: UsageWindowType) -> UsageWindow? {
        guard let dict = raw as? [String: Any],
              let usedPercent = dict["used_percent"] as? Double else { return nil }
        let resetsAt: Date
        if let epoch = dict["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = dict["resets_at"] as? Int {
            resetsAt = Date(timeIntervalSince1970: Double(epoch))
        } else {
            resetsAt = Date().addingTimeInterval(type.totalDuration)
        }
        return UsageWindow(utilization: usedPercent, resetsAt: resetsAt, windowType: type)
    }
}
#endif
