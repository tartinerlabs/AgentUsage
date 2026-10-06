#if os(macOS)
import Foundation
import AgentUsageKit

/// Reads Gemini CLI's legacy JSON and append-only JSONL chat recordings.
/// Only `tmp/<project>/chats` is scanned; Antigravity's separate data is excluded.
actor GeminiLogSource: UsageLogSource {
    nonisolated let provider: Provider = .gemini
    private let directory: URL
    private struct CachedFile {
        let modified: Date
        let size: Int
        let entries: [ProviderUsageEntry]
    }
    private var cache: [URL: CachedFile] = [:]

    init(directory: URL = Constants.geminiSessionsDirectory) {
        self.directory = directory
    }

    func fetchEntries(since: Date) async throws -> [ProviderUsageEntry] {
        let files = try discoverFiles()
        var entries: [ProviderUsageEntry] = []
        var seen = Set<String>()
        for file in files {
            try Task.checkCancellation()
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, let size = values.fileSize else { continue }
            let parsed: [ProviderUsageEntry]
            if let cached = cache[file], cached.modified == modified, cached.size == size {
                parsed = cached.entries
            } else {
                guard let data = try? Data(contentsOf: file) else { continue }
                parsed = Self.parse(data: data, jsonl: file.pathExtension == "jsonl")
                cache[file] = CachedFile(modified: modified, size: size, entries: parsed)
            }
            entries += parsed.filter { $0.timestamp >= since && seen.insert($0.dedupKey).inserted }
        }
        let discovered = Set(files)
        cache = cache.filter { discovered.contains($0.key) }
        return entries
    }

    private func discoverFiles() throws -> [URL] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            throw UsageLogSourceError.unavailable
        }
        var result: [URL] = []
        for project in projects {
            guard let files = manager.enumerator(
                at: project.appendingPathComponent("chats"), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in files where ["json", "jsonl"].contains(file.pathExtension) {
                result.append(file)
            }
        }
        // Gemini migrates JSON recordings to JSONL and may leave the older copy.
        // Prefer the current recording when both contain the same message ID.
        return result.sorted {
            if $0.pathExtension != $1.pathExtension { return $0.pathExtension == "jsonl" }
            return $0.path < $1.path
        }
    }

    nonisolated static func parse(data: Data, jsonl: Bool) -> [ProviderUsageEntry] {
        var metadata: [String: Any] = [:]
        var messages: [String: [String: Any]] = [:]
        var order: [String] = []
        func add(_ message: [String: Any]) {
            guard let id = message["id"] as? String, !id.isEmpty else { return }
            if messages[id] == nil { order.append(id) }
            messages[id] = message
        }
        let records: [[String: Any]]
        if jsonl {
            records = data.split(separator: 10).compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
            }
        } else {
            guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
            records = [record]
        }
        for record in records {
            if let rewind = record["$rewindTo"] as? String {
                let removed = order.firstIndex(of: rewind).map { Array(order[$0...]) } ?? order
                for id in removed { messages[id] = nil }
                order.removeAll { removed.contains($0) }
            } else if let patch = record["$patch"] as? [String: Any] {
                let updates = (patch["updates"] as? [[String: Any]]) ?? [patch]
                for update in updates {
                    guard let id = update["id"] as? String, var existing = messages[id] else { continue }
                    existing.merge(update) { _, new in new }
                    messages[id] = existing
                }
                for id in patch["removeIds"] as? [String] ?? [] {
                    messages[id] = nil
                    order.removeAll { $0 == id }
                }
            } else if record["id"] is String {
                add(record)
            } else {
                let update = (record["$set"] as? [String: Any]) ?? record
                metadata.merge(update) { _, new in new }
                for message in update["messages"] as? [[String: Any]] ?? [] { add(message) }
            }
        }
        guard let session = metadata["sessionId"] as? String, !session.isEmpty else { return [] }
        return order.compactMap { id in
            guard let message = messages[id], message["type"] as? String == "gemini",
                  let model = message["model"] as? String, !model.isEmpty,
                  let timestamp = GoogleUsageService.parseDate(message["timestamp"] as? String),
                  let tokens = message["tokens"] as? [String: Any] else { return nil }
            func count(_ key: String) -> Int { max(0, tokens[key] as? Int ?? 0) }
            let cached = min(count("cached"), count("input"))
            let counts = TokenCount(
                inputTokens: count("input") - cached, outputTokens: count("output"),
                cacheCreationTokens: 0, cacheReadTokens: cached, reasoningTokens: count("thoughts")
            )
            guard counts.totalTokens > 0 else { return nil }
            return ProviderUsageEntry(
                provider: .gemini, model: model, tokens: counts, timestamp: timestamp,
                dedupKey: "gemini:\(session):\(id)", sessionID: session,
                isSubagentSession: metadata["kind"] as? String == "subagent"
            )
        }
    }
}
#endif
