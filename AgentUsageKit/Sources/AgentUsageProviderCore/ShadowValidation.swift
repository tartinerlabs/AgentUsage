// Shadow validation architecture adapted from steipete/CodexBar provider diagnostics.
// Upstream commit: 98de97833505a6213ec2cf3c2c6d528443b77d8d (MIT).

import AgentUsageKit
import Foundation

public enum ShadowMismatchCategory: String, Codable, CaseIterable, Sendable {
    case missingAuthoritativeWindow
    case missingShadowWindow
    case utilization
    case resetTime
    case plan
    case source
}

public enum ShadowTimingBucket: String, Codable, Sendable {
    case underOneSecond
    case oneToFiveSeconds
    case fiveToTwentySeconds
    case overTwentySeconds

    public init(duration: Duration) {
        let seconds = duration.components.seconds
        switch seconds {
        case ..<1: self = .underOneSecond
        case 1..<5: self = .oneToFiveSeconds
        case 5..<20: self = .fiveToTwentySeconds
        default: self = .overTwentySeconds
        }
    }
}

/// Contains categories only. It deliberately has no fields capable of holding
/// utilization, reset timestamps, response bodies, credentials, or user paths.
public struct ShadowDiagnosticEntry: Codable, Sendable, Equatable {
    public let provider: Provider
    public let recordedHour: Date
    public let strategyIDs: [String]
    public let timing: ShadowTimingBucket
    public let mismatches: [ShadowMismatchCategory]
    public let failureCategory: ProviderFailureCategory?

    public init(
        provider: Provider,
        recordedAt: Date,
        strategyIDs: [String],
        timing: ShadowTimingBucket,
        mismatches: [ShadowMismatchCategory],
        failureCategory: ProviderFailureCategory?
    ) {
        self.provider = provider
        self.recordedHour = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: recordedAt)?.start
            ?? recordedAt
        self.strategyIDs = Array(strategyIDs.prefix(8))
        self.timing = timing
        self.mismatches = Array(Set(mismatches)).sorted { $0.rawValue < $1.rawValue }
        self.failureCategory = failureCategory
    }
}

public enum ShadowComparator {
    public static func compare(
        authoritative: ProviderUsageSnapshot,
        shadow: ProviderUsageSnapshot,
        authoritativeSource: String? = nil,
        shadowSource: String? = nil,
        utilizationTolerance: Double = 1,
        resetTolerance: TimeInterval = 120
    ) -> [ShadowMismatchCategory] {
        var mismatches = Set<ShadowMismatchCategory>()
        let authoritativeWindows = Dictionary(uniqueKeysWithValues: authoritative.windows.map { ($0.windowID, $0) })
        let shadowWindows = Dictionary(uniqueKeysWithValues: shadow.windows.map { ($0.windowID, $0) })

        for (id, window) in authoritativeWindows {
            guard let candidate = shadowWindows[id] else {
                mismatches.insert(.missingShadowWindow)
                continue
            }
            if abs(window.utilization - candidate.utilization) > utilizationTolerance {
                mismatches.insert(.utilization)
            }
            if abs(window.resetsAt.timeIntervalSince(candidate.resetsAt)) > resetTolerance {
                mismatches.insert(.resetTime)
            }
        }
        if shadowWindows.keys.contains(where: { authoritativeWindows[$0] == nil }) {
            mismatches.insert(.missingAuthoritativeWindow)
        }
        if authoritative.planName != shadow.planName { mismatches.insert(.plan) }
        if let authoritativeSource, let shadowSource, authoritativeSource != shadowSource {
            mismatches.insert(.source)
        }
        return mismatches.sorted { $0.rawValue < $1.rawValue }
    }
}

public actor ShadowDiagnosticStore {
    private let fileURL: URL
    private let capacity: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL, capacity: Int = 500) {
        self.fileURL = fileURL
        self.capacity = max(1, capacity)
    }

    public func append(_ entry: ShadowDiagnosticEntry) throws {
        var entries = try load()
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        try write(entries)
    }

    public func load() throws -> [ShadowDiagnosticEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([ShadowDiagnosticEntry].self, from: Data(contentsOf: fileURL))
    }

    public func export(to destination: URL) throws {
        try write(try load(), to: destination)
    }

    private func write(_ entries: [ShadowDiagnosticEntry], to destination: URL? = nil) throws {
        let target = destination ?? fileURL
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(entries).write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
