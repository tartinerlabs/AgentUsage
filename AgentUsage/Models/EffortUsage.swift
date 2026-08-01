//
//  EffortUsage.swift
//  AgentUsage
//
//  Provider-neutral session effort aggregation.
//

import Foundation
import AgentUsageKit

/// One effort-bearing (or explicitly unclassified) local usage record.
///
/// Claude contributes one sample per deduplicated assistant usage record. Codex
/// contributes its existing single cumulative record per session.
nonisolated struct EffortUsageSample: Sendable {
    let provider: Provider
    let sessionID: String
    let effortLevel: EffortLevel?
    let timestamp: Date
    let isSubagentSession: Bool

    init(
        provider: Provider,
        sessionID: String,
        effortLevel: EffortLevel?,
        timestamp: Date,
        isSubagentSession: Bool = false
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.effortLevel = effortLevel
        self.timestamp = timestamp
        self.isSubagentSession = isSubagentSession
    }
}

/// One normalized session after request-level effort samples are collapsed.
nonisolated struct EffortSessionSummary: Sendable {
    let provider: Provider
    let sessionID: String
    let latestTimestamp: Date
    let effortLevel: EffortLevel?
}

/// Collapses request-level usage into session-count effort distributions.
nonisolated enum EffortUsageAggregator {
    private struct SessionKey: Hashable {
        let provider: Provider
        let sessionID: String
    }

    private struct SessionAccumulator {
        var latestTimestamp: Date
        var levelCounts: [EffortLevel: Int]
    }

    /// Builds every requested period in one pass over normalized usage samples.
    static func summaries(
        from samples: [EffortUsageSample],
        periods: [EffortPeriod] = EffortPeriod.allCases,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Provider: [EffortPeriodSummary]] {
        let sessions = sessionSummaries(from: samples)

        var result: [Provider: [EffortPeriodSummary]] = [:]
        for provider in Set(sessions.map(\.provider)) {
            let providerSessions = sessions.filter { $0.provider == provider }
            result[provider] = periods.map { period in
                let startDate = period.startDate(relativeTo: now, calendar: calendar)
                let inPeriod = providerSessions.filter { $0.latestTimestamp >= startDate }
                var counts: [EffortLevel: Int] = [:]
                var unclassified = 0

                for session in inPeriod {
                    guard let level = session.effortLevel else {
                        unclassified += 1
                        continue
                    }
                    counts[level, default: 0] += 1
                }

                let levels = counts
                    .map { EffortLevelCount(level: $0.key, sessionCount: $0.value) }
                    .sorted {
                        if $0.level.sortOrder == $1.level.sortOrder {
                            return $0.level.rawValue < $1.level.rawValue
                        }
                        return $0.level.sortOrder < $1.level.sortOrder
                    }

                return EffortPeriodSummary(
                    period: period,
                    levels: levels,
                    classifiedSessionCount: counts.values.reduce(0, +),
                    unclassifiedSessionCount: unclassified
                )
            }
        }
        return result
    }

    /// Exposes the same session semantics to consumers that need non-rolling
    /// buckets, such as the blog's durable daily aggregates.
    static func sessionSummaries(from samples: [EffortUsageSample]) -> [EffortSessionSummary] {
        var sessions: [SessionKey: SessionAccumulator] = [:]

        for sample in samples where !sample.isSubagentSession {
            // Request rows without a stable session identity cannot contribute to
            // session-level coverage without inflating one request into one session.
            let sessionID = sample.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else { continue }
            let key = SessionKey(provider: sample.provider, sessionID: sessionID)
            var accumulator = sessions[key] ?? SessionAccumulator(
                latestTimestamp: sample.timestamp,
                levelCounts: [:]
            )
            accumulator.latestTimestamp = max(accumulator.latestTimestamp, sample.timestamp)
            if let effortLevel = sample.effortLevel {
                accumulator.levelCounts[effortLevel, default: 0] += 1
            }
            sessions[key] = accumulator
        }

        return sessions.map { key, accumulator in
            EffortSessionSummary(
                provider: key.provider,
                sessionID: key.sessionID,
                latestTimestamp: accumulator.latestTimestamp,
                effortLevel: dominantLevel(in: accumulator.levelCounts)
            )
        }
        .sorted {
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.sessionID < $1.sessionID
        }
    }

    private static func dominantLevel(in counts: [EffortLevel: Int]) -> EffortLevel? {
        guard let maximum = counts.values.max() else { return nil }
        let leaders = counts.compactMap { level, count in
            count == maximum ? level : nil
        }
        return leaders.count == 1 ? leaders[0] : .mixed
    }
}

nonisolated extension EffortPeriod {
    func startDate(relativeTo now: Date, calendar: Calendar) -> Date {
        switch self {
        case .today:
            calendar.startOfDay(for: now)
        case .last7Days:
            calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90Days:
            calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .last180Days:
            calendar.date(byAdding: .day, value: -180, to: now) ?? now
        case .lastYear:
            calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }
}

nonisolated extension UsagePeriod {
    var effortPeriod: EffortPeriod {
        switch self {
        case .today: .today
        case .last7Days: .last7Days
        case .last30Days: .last30Days
        case .last90Days: .last90Days
        case .last180Days: .last180Days
        case .lastYear: .lastYear
        }
    }
}
