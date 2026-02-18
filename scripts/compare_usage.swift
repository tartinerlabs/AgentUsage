#!/usr/bin/swift

import Foundation
import CryptoKit

struct CLIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct TokenTotals: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func add(_ other: TokenTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
    }
}

struct ModelAggregate: Codable {
    var modelRaw: String
    var modelCanonical: String
    var tokens: TokenTotals
    var costRecomputedUSD: Double
}

struct SideAggregate: Codable {
    var totals: TokenTotals
    var totalCostRecomputedUSD: Double
    var byCanonical: [String: ModelAggregate]
    var byRaw: [String: ModelAggregate]
}

struct DeltaAggregate: Codable {
    var inputTokensDelta: Int
    var outputTokensDelta: Int
    var cacheCreationTokensDelta: Int
    var cacheReadTokensDelta: Int
    var totalTokensDelta: Int
    var costDeltaUSD: Double
}

struct ComparisonSummary: Codable {
    struct Metadata: Codable {
        var generatedAt: String
        var timezone: String
        var start: String
        var end: String
        var windowType: String
        var ccusageCommand: [String]
        var gitCommit: String?
    }

    var metadata: Metadata
    var claudeMeter: SideAggregate
    var ccusage: SideAggregate
    var totalDelta: DeltaAggregate
    var perModelDelta: [String: DeltaAggregate]
    var hasMismatch: Bool
}

struct Diagnostics: Codable {
    struct ParseStats: Codable {
        var filesScanned: Int
        var linesScanned: Int
        var assistantEntriesParsed: Int
        var entriesWithinWindow: Int
        var dedupDuplicatesSkipped: Int
        var fallbackMessageIDCount: Int
        var fallbackRequestIDCount: Int
    }

    struct BoundaryEntry: Codable {
        var timestamp: String
        var model: String
        var compositeID: String
    }

    var parseStats: ParseStats
    var rawModelsOnlyInClaudeMeter: [String]
    var rawModelsOnlyInCCUsage: [String]
    var canonicalBucketsWithMultipleRawModelsClaudeMeter: [String: [String]]
    var canonicalBucketsWithMultipleRawModelsCCUsage: [String: [String]]
    var startBoundaryEntries: [BoundaryEntry]
    var endBoundaryEntries: [BoundaryEntry]
}

struct Rates {
    var inputPerMTok: Double
    var outputPerMTok: Double
    var cacheWritePerMTok: Double
    var cacheReadPerMTok: Double
}

let opus45 = Rates(inputPerMTok: 5.0, outputPerMTok: 25.0, cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50)
let sonnet45 = Rates(inputPerMTok: 3.0, outputPerMTok: 15.0, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30)
let sonnet4 = Rates(inputPerMTok: 3.0, outputPerMTok: 15.0, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30)
let haiku45 = Rates(inputPerMTok: 1.0, outputPerMTok: 5.0, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.10)
let haiku35 = Rates(inputPerMTok: 0.80, outputPerMTok: 4.0, cacheWritePerMTok: 1.0, cacheReadPerMTok: 0.08)

func canonicalModel(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.contains("opus-4-6") || lower.contains("opus-4.6") { return "opus-4-5" }
    if lower.contains("opus-4-5") || lower.contains("opus-4.5") { return "opus-4-5" }
    if lower.contains("sonnet-4-5") || lower.contains("sonnet-4.5") { return "sonnet-4-5" }
    if lower.contains("sonnet-4") { return "sonnet-4" }
    if lower.contains("haiku-4-5") || lower.contains("haiku-4.5") { return "haiku-4-5" }
    if lower.contains("haiku-3-5") || lower.contains("haiku-3.5") || lower.contains("haiku") { return "haiku-3-5" }
    return "unknown"
}

func rates(for rawModel: String) -> Rates? {
    switch canonicalModel(rawModel) {
    case "opus-4-5": return opus45
    case "sonnet-4-5": return sonnet45
    case "sonnet-4": return sonnet4
    case "haiku-4-5": return haiku45
    case "haiku-3-5": return haiku35
    default: return nil
    }
}

func calculateCost(_ tokens: TokenTotals, rawModel: String) -> Double {
    guard let r = rates(for: rawModel) else { return 0 }
    let input = Double(tokens.inputTokens) * r.inputPerMTok / 1_000_000
    let output = Double(tokens.outputTokens) * r.outputPerMTok / 1_000_000
    let cacheWrite = Double(tokens.cacheCreationTokens) * r.cacheWritePerMTok / 1_000_000
    let cacheRead = Double(tokens.cacheReadTokens) * r.cacheReadPerMTok / 1_000_000
    return input + output + cacheWrite + cacheRead
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func shellOutput(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = args

    let stdout = Pipe()
    let stderr = Pipe()
    proc.standardOutput = stdout
    proc.standardError = stderr
    try proc.run()
    proc.waitUntilExit()

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    return (
        proc.terminationStatus,
        String(data: outData, encoding: .utf8) ?? "",
        String(data: errData, encoding: .utf8) ?? ""
    )
}

func gitCommit() -> String? {
    guard let result = try? shellOutput(["git", "rev-parse", "--short", "HEAD"]), result.status == 0 else {
        return nil
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoNoFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseTimestamp(_ raw: String) -> Date? {
    isoFractional.date(from: raw) ?? isoNoFraction.date(from: raw)
}

func isoString(_ date: Date) -> String {
    isoFractional.string(from: date)
}

func parseArgs() throws -> (start: Date, end: Date, timezone: TimeZone, outputDir: URL, windowType: String) {
    let args = Array(CommandLine.arguments.dropFirst())

    var startRaw: String?
    var endRaw: String?
    var tzRaw: String?
    var outputRaw = "./usage-comparison"
    var useLast30d = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--start":
            i += 1
            guard i < args.count else { throw CLIError(message: "Missing value for --start") }
            startRaw = args[i]
        case "--end":
            i += 1
            guard i < args.count else { throw CLIError(message: "Missing value for --end") }
            endRaw = args[i]
        case "--tz", "--timezone":
            i += 1
            guard i < args.count else { throw CLIError(message: "Missing value for --tz") }
            tzRaw = args[i]
        case "--output":
            i += 1
            guard i < args.count else { throw CLIError(message: "Missing value for --output") }
            outputRaw = args[i]
        case "--last-30d":
            useLast30d = true
        case "--help", "-h":
            print("""
Usage:
  swift scripts/compare_usage.swift --last-30d [--tz <iana>] [--output <dir>]
  swift scripts/compare_usage.swift --start <iso8601> --end <iso8601> [--tz <iana>] [--output <dir>]

Options:
  --last-30d           Use rolling last 30 days up to now (default when start/end omitted)
  --start <iso8601>    Inclusive start timestamp
  --end <iso8601>      Inclusive end timestamp
  --tz <iana>          Timezone ID for ccusage grouping (default: system timezone)
  --output <dir>       Output directory (default: ./usage-comparison)
""")
            exit(0)
        default:
            throw CLIError(message: "Unknown argument: \(args[i])")
        }
        i += 1
    }

    let timezone = tzRaw.flatMap(TimeZone.init(identifier:)) ?? .current
    let now = Date()

    let start: Date
    let end: Date
    let windowType: String

    if let s = startRaw, let e = endRaw {
        guard let sDate = parseTimestamp(s), let eDate = parseTimestamp(e) else {
            throw CLIError(message: "--start/--end must be ISO8601 timestamps")
        }
        guard sDate <= eDate else {
            throw CLIError(message: "--start must be <= --end")
        }
        start = sDate
        end = eDate
        windowType = "custom"
    } else {
        _ = useLast30d
        guard let s = Calendar.current.date(byAdding: .day, value: -30, to: now) else {
            throw CLIError(message: "Failed to compute last-30d window")
        }
        start = s
        end = now
        windowType = "last_30_days_rolling"
    }

    return (start, end, timezone, URL(fileURLWithPath: outputRaw), windowType)
}

struct Entry {
    var timestamp: Date
    var modelRaw: String
    var tokens: TokenTotals
    var compositeID: String
}

func loadClaudeMeterEntries(start: Date, end: Date) throws -> ([Entry], Diagnostics.ParseStats, [Diagnostics.BoundaryEntry], [Diagnostics.BoundaryEntry]) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let directories = [
        home.appendingPathComponent(".claude/projects"),
        home.appendingPathComponent(".config/claude/projects")
    ]

    var files: [URL] = []
    for dir in directories where FileManager.default.fileExists(atPath: dir.path) {
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                files.append(file)
            }
        }
    }

    var seen = Set<String>()
    var entries: [Entry] = []
    var linesScanned = 0
    var assistantParsed = 0
    var withinWindow = 0
    var duplicates = 0
    var fallbackMessage = 0
    var fallbackRequest = 0

    let startWindow = start.addingTimeInterval(-300)
    let startWindowEnd = start.addingTimeInterval(300)
    let endWindow = end.addingTimeInterval(-300)
    let endWindowEnd = end.addingTimeInterval(300)
    var startBoundary: [Diagnostics.BoundaryEntry] = []
    var endBoundary: [Diagnostics.BoundaryEntry] = []

    for file in files {
        let data = try Data(contentsOf: file)
        guard let content = String(data: data, encoding: .utf8) else { continue }

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            linesScanned += 1
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (json["type"] as? String) == "assistant",
                  let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any],
                  let tsRaw = json["timestamp"] as? String,
                  let timestamp = parseTimestamp(tsRaw) else {
                continue
            }

            assistantParsed += 1

            let fallback = "log-\(sha256Hex(lineData))"
            let messageID: String
            if let id = message["id"] as? String {
                messageID = id
            } else {
                fallbackMessage += 1
                messageID = fallback
            }

            let requestID: String
            if let id = (json["requestId"] as? String) ?? (json["request_id"] as? String) {
                requestID = id
            } else {
                fallbackRequest += 1
                requestID = fallback
            }

            let compositeID = "\(messageID):\(requestID)"
            if seen.contains(compositeID) {
                duplicates += 1
                continue
            }
            seen.insert(compositeID)

            if timestamp >= startWindow && timestamp <= startWindowEnd, startBoundary.count < 20 {
                startBoundary.append(.init(timestamp: isoString(timestamp), model: model, compositeID: compositeID))
            }
            if timestamp >= endWindow && timestamp <= endWindowEnd, endBoundary.count < 20 {
                endBoundary.append(.init(timestamp: isoString(timestamp), model: model, compositeID: compositeID))
            }

            guard timestamp >= start && timestamp <= end else { continue }
            withinWindow += 1

            let tokens = TokenTotals(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
            )
            entries.append(.init(timestamp: timestamp, modelRaw: model, tokens: tokens, compositeID: compositeID))
        }
    }

    let stats = Diagnostics.ParseStats(
        filesScanned: files.count,
        linesScanned: linesScanned,
        assistantEntriesParsed: assistantParsed,
        entriesWithinWindow: withinWindow,
        dedupDuplicatesSkipped: duplicates,
        fallbackMessageIDCount: fallbackMessage,
        fallbackRequestIDCount: fallbackRequest
    )

    return (entries, stats, startBoundary, endBoundary)
}

func aggregate(entries: [Entry]) -> SideAggregate {
    var totals = TokenTotals()
    var totalCost = 0.0
    var byCanonical: [String: ModelAggregate] = [:]
    var byRaw: [String: ModelAggregate] = [:]

    for e in entries {
        totals.add(e.tokens)
        let cost = calculateCost(e.tokens, rawModel: e.modelRaw)
        totalCost += cost

        let canonical = canonicalModel(e.modelRaw)
        if var existing = byCanonical[canonical] {
            existing.tokens.add(e.tokens)
            existing.costRecomputedUSD += cost
            byCanonical[canonical] = existing
        } else {
            byCanonical[canonical] = ModelAggregate(modelRaw: canonical, modelCanonical: canonical, tokens: e.tokens, costRecomputedUSD: cost)
        }

        if var existing = byRaw[e.modelRaw] {
            existing.tokens.add(e.tokens)
            existing.costRecomputedUSD += cost
            byRaw[e.modelRaw] = existing
        } else {
            byRaw[e.modelRaw] = ModelAggregate(modelRaw: e.modelRaw, modelCanonical: canonical, tokens: e.tokens, costRecomputedUSD: cost)
        }
    }

    return SideAggregate(totals: totals, totalCostRecomputedUSD: totalCost, byCanonical: byCanonical, byRaw: byRaw)
}

struct CCUsageMonthlyResponse: Codable {
    struct Monthly: Codable {
        struct Breakdown: Codable {
            var modelName: String
            var inputTokens: Int
            var outputTokens: Int
            var cacheCreationTokens: Int
            var cacheReadTokens: Int
        }
        var modelBreakdowns: [Breakdown]
    }
    var monthly: [Monthly]
}

func loadCCUsageAggregate(start: Date, end: Date, timezone: TimeZone) throws -> (SideAggregate, [String]) {
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = Calendar(identifier: .gregorian)
    dayFormatter.timeZone = timezone
    dayFormatter.dateFormat = "yyyyMMdd"

    let since = dayFormatter.string(from: start)
    let until = dayFormatter.string(from: end)

    let args = [
        "bunx", "ccusage", "monthly",
        "--json",
        "--mode", "calculate",
        "--offline",
        "--breakdown",
        "--order", "asc",
        "--timezone", timezone.identifier,
        "--since", since,
        "--until", until
    ]

    let result = try shellOutput(args)
    guard result.status == 0 else {
        throw CLIError(message: "ccusage failed (exit \(result.status)): \(result.stderr)")
    }

    guard let data = result.stdout.data(using: .utf8) else {
        throw CLIError(message: "Failed to parse ccusage stdout as UTF-8")
    }

    let decoded: CCUsageMonthlyResponse
    do {
        decoded = try JSONDecoder().decode(CCUsageMonthlyResponse.self, from: data)
    } catch {
        throw CLIError(message: "Failed to decode ccusage JSON: \(error)")
    }

    var entries: [Entry] = []
    for month in decoded.monthly {
        for breakdown in month.modelBreakdowns {
            let tokens = TokenTotals(
                inputTokens: breakdown.inputTokens,
                outputTokens: breakdown.outputTokens,
                cacheCreationTokens: breakdown.cacheCreationTokens,
                cacheReadTokens: breakdown.cacheReadTokens
            )
            entries.append(Entry(timestamp: end, modelRaw: breakdown.modelName, tokens: tokens, compositeID: "ccusage:\(breakdown.modelName)"))
        }
    }

    return (aggregate(entries: entries), args)
}

func delta(_ left: SideAggregate, _ right: SideAggregate) -> (DeltaAggregate, [String: DeltaAggregate], Bool) {
    let total = DeltaAggregate(
        inputTokensDelta: left.totals.inputTokens - right.totals.inputTokens,
        outputTokensDelta: left.totals.outputTokens - right.totals.outputTokens,
        cacheCreationTokensDelta: left.totals.cacheCreationTokens - right.totals.cacheCreationTokens,
        cacheReadTokensDelta: left.totals.cacheReadTokens - right.totals.cacheReadTokens,
        totalTokensDelta: left.totals.totalTokens - right.totals.totalTokens,
        costDeltaUSD: left.totalCostRecomputedUSD - right.totalCostRecomputedUSD
    )

    let allKeys = Set(left.byCanonical.keys).union(right.byCanonical.keys)
    var perModel: [String: DeltaAggregate] = [:]
    var hasMismatch = false

    for key in allKeys.sorted() {
        let l = left.byCanonical[key]
        let r = right.byCanonical[key]
        let d = DeltaAggregate(
            inputTokensDelta: (l?.tokens.inputTokens ?? 0) - (r?.tokens.inputTokens ?? 0),
            outputTokensDelta: (l?.tokens.outputTokens ?? 0) - (r?.tokens.outputTokens ?? 0),
            cacheCreationTokensDelta: (l?.tokens.cacheCreationTokens ?? 0) - (r?.tokens.cacheCreationTokens ?? 0),
            cacheReadTokensDelta: (l?.tokens.cacheReadTokens ?? 0) - (r?.tokens.cacheReadTokens ?? 0),
            totalTokensDelta: (l?.tokens.totalTokens ?? 0) - (r?.tokens.totalTokens ?? 0),
            costDeltaUSD: (l?.costRecomputedUSD ?? 0) - (r?.costRecomputedUSD ?? 0)
        )
        perModel[key] = d
        if d.inputTokensDelta != 0 || d.outputTokensDelta != 0 || d.cacheCreationTokensDelta != 0 || d.cacheReadTokensDelta != 0 || d.totalTokensDelta != 0 || abs(d.costDeltaUSD) > 0.000001 {
            hasMismatch = true
        }
    }

    if total.inputTokensDelta != 0 || total.outputTokensDelta != 0 || total.cacheCreationTokensDelta != 0 || total.cacheReadTokensDelta != 0 || total.totalTokensDelta != 0 || abs(total.costDeltaUSD) > 0.000001 {
        hasMismatch = true
    }

    return (total, perModel, hasMismatch)
}

func canonicalCollisionMap(_ byRaw: [String: ModelAggregate]) -> [String: [String]] {
    var map: [String: [String]] = [:]
    for (raw, aggregate) in byRaw {
        map[aggregate.modelCanonical, default: []].append(raw)
    }
    for key in map.keys {
        map[key] = map[key]?.sorted()
    }
    return map.filter { $0.value.count > 1 }
}

func markdownTable(summary: ComparisonSummary) -> String {
    var lines: [String] = []
    lines.append("# Usage Comparison")
    lines.append("")
    lines.append("- Generated: \(summary.metadata.generatedAt)")
    lines.append("- Window: \(summary.metadata.start) to \(summary.metadata.end) (\(summary.metadata.timezone))")
    lines.append("- Window type: \(summary.metadata.windowType)")
    if let commit = summary.metadata.gitCommit, !commit.isEmpty {
        lines.append("- Git commit: \(commit)")
    }
    lines.append("")

    lines.append("## Totals")
    lines.append("")
    lines.append("| Metric | ClaudeMeter | ccusage | Delta |")
    lines.append("|---|---:|---:|---:|")
    lines.append("| Input tokens | \(summary.claudeMeter.totals.inputTokens) | \(summary.ccusage.totals.inputTokens) | \(summary.totalDelta.inputTokensDelta) |")
    lines.append("| Output tokens | \(summary.claudeMeter.totals.outputTokens) | \(summary.ccusage.totals.outputTokens) | \(summary.totalDelta.outputTokensDelta) |")
    lines.append("| Cache create tokens | \(summary.claudeMeter.totals.cacheCreationTokens) | \(summary.ccusage.totals.cacheCreationTokens) | \(summary.totalDelta.cacheCreationTokensDelta) |")
    lines.append("| Cache read tokens | \(summary.claudeMeter.totals.cacheReadTokens) | \(summary.ccusage.totals.cacheReadTokens) | \(summary.totalDelta.cacheReadTokensDelta) |")
    lines.append("| Total tokens | \(summary.claudeMeter.totals.totalTokens) | \(summary.ccusage.totals.totalTokens) | \(summary.totalDelta.totalTokensDelta) |")
    lines.append("| Recomputed cost (USD) | \(String(format: "%.4f", summary.claudeMeter.totalCostRecomputedUSD)) | \(String(format: "%.4f", summary.ccusage.totalCostRecomputedUSD)) | \(String(format: "%.4f", summary.totalDelta.costDeltaUSD)) |")
    lines.append("")

    lines.append("## Per Canonical Model")
    lines.append("")
    lines.append("| Model | CM total tokens | CC total tokens | Delta tokens | CM cost | CC cost | Delta cost |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for key in Set(summary.claudeMeter.byCanonical.keys).union(summary.ccusage.byCanonical.keys).sorted() {
        let l = summary.claudeMeter.byCanonical[key]
        let r = summary.ccusage.byCanonical[key]
        lines.append("| \(key) | \(l?.tokens.totalTokens ?? 0) | \(r?.tokens.totalTokens ?? 0) | \((l?.tokens.totalTokens ?? 0) - (r?.tokens.totalTokens ?? 0)) | \(String(format: "%.4f", l?.costRecomputedUSD ?? 0)) | \(String(format: "%.4f", r?.costRecomputedUSD ?? 0)) | \(String(format: "%.4f", (l?.costRecomputedUSD ?? 0) - (r?.costRecomputedUSD ?? 0))) |")
    }

    return lines.joined(separator: "\n") + "\n"
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url)
}

do {
    let args = try parseArgs()
    let fm = FileManager.default
    try fm.createDirectory(at: args.outputDir, withIntermediateDirectories: true)

    let (cmEntries, stats, startBoundary, endBoundary) = try loadClaudeMeterEntries(start: args.start, end: args.end)
    let cmAggregate = aggregate(entries: cmEntries)

    let (ccAggregate, ccCommand) = try loadCCUsageAggregate(start: args.start, end: args.end, timezone: args.timezone)

    let (totalDelta, perModelDelta, hasMismatch) = delta(cmAggregate, ccAggregate)

    let summary = ComparisonSummary(
        metadata: .init(
            generatedAt: isoString(Date()),
            timezone: args.timezone.identifier,
            start: isoString(args.start),
            end: isoString(args.end),
            windowType: args.windowType,
            ccusageCommand: ccCommand,
            gitCommit: gitCommit()
        ),
        claudeMeter: cmAggregate,
        ccusage: ccAggregate,
        totalDelta: totalDelta,
        perModelDelta: perModelDelta,
        hasMismatch: hasMismatch
    )

    let diagnostics = Diagnostics(
        parseStats: stats,
        rawModelsOnlyInClaudeMeter: Array(Set(cmAggregate.byRaw.keys).subtracting(ccAggregate.byRaw.keys)).sorted(),
        rawModelsOnlyInCCUsage: Array(Set(ccAggregate.byRaw.keys).subtracting(cmAggregate.byRaw.keys)).sorted(),
        canonicalBucketsWithMultipleRawModelsClaudeMeter: canonicalCollisionMap(cmAggregate.byRaw),
        canonicalBucketsWithMultipleRawModelsCCUsage: canonicalCollisionMap(ccAggregate.byRaw),
        startBoundaryEntries: startBoundary,
        endBoundaryEntries: endBoundary
    )

    try writeJSON(summary, to: args.outputDir.appendingPathComponent("comparison-summary.json"))
    try writeJSON(diagnostics, to: args.outputDir.appendingPathComponent("comparison-diagnostics.json"))
    try markdownTable(summary: summary).data(using: .utf8)?.write(to: args.outputDir.appendingPathComponent("comparison-table.md"))

    print("Wrote comparison artifacts to: \(args.outputDir.path)")
    print("- comparison-summary.json")
    print("- comparison-diagnostics.json")
    print("- comparison-table.md")
    print("Has mismatch: \(hasMismatch ? "yes" : "no")")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
