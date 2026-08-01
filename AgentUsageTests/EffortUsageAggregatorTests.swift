import Foundation
import Testing
import AgentUsageKit
@testable import AgentUsage

@Suite("Effort usage aggregation")
struct EffortUsageAggregatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func groupsBySessionUsesDominantLevelAndMarksExactTiesMixed() throws {
        let samples = [
            sample(provider: .claude, session: "mostly-high", level: .high, age: 100),
            sample(provider: .claude, session: "mostly-high", level: .high, age: 90),
            sample(provider: .claude, session: "mostly-high", level: .medium, age: 80),
            sample(provider: .claude, session: "tie", level: .low, age: 70),
            sample(provider: .claude, session: "tie", level: .medium, age: 60),
        ]

        let summary = try #require(
            EffortUsageAggregator.summaries(from: samples, periods: [.today], now: now)[.claude]?.first
        )

        #expect(summary.classifiedSessionCount == 2)
        #expect(summary.unclassifiedSessionCount == 0)
        #expect(summary.levels.first(where: { $0.level == .high })?.sessionCount == 1)
        #expect(summary.levels.first(where: { $0.level == .mixed })?.sessionCount == 1)
    }

    @Test func excludesSubagentsAndDisclosesSessionsWithoutEffort() throws {
        let samples = [
            sample(provider: .claude, session: "classified", level: .medium, age: 100),
            sample(provider: .claude, session: "unknown", level: nil, age: 90),
            sample(provider: .claude, session: "subagent", level: .xhigh, age: 80, subagent: true),
        ]

        let summary = try #require(
            EffortUsageAggregator.summaries(from: samples, periods: [.today], now: now)[.claude]?.first
        )

        #expect(summary.classifiedSessionCount == 1)
        #expect(summary.unclassifiedSessionCount == 1)
        #expect(summary.totalSessionCount == 2)
        #expect(summary.levels == [EffortLevelCount(level: .medium, sessionCount: 1)])
    }

    @Test func assignsSessionToPeriodUsingItsLatestUsage() throws {
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        let samples = [
            sample(provider: .codex, session: "continued", level: .low, age: eightDays),
            sample(provider: .codex, session: "continued", level: .xhigh, age: 60),
            sample(provider: .codex, session: "old", level: .medium, age: eightDays),
        ]

        let summary = try #require(
            EffortUsageAggregator.summaries(from: samples, periods: [.last7Days], now: now)[.codex]?.first
        )

        #expect(summary.classifiedSessionCount == 1)
        #expect(summary.levels.map(\.level) == [.mixed])
    }

    @Test func keepsProvidersAndPeriodsIndependent() throws {
        let samples = [
            sample(provider: .claude, session: "claude", level: .high, age: 60),
            sample(provider: .codex, session: "codex", level: .xhigh, age: 60),
        ]
        let summaries = EffortUsageAggregator.summaries(
            from: samples,
            periods: [.today, .last30Days],
            now: now
        )

        #expect(summaries[.claude]?.count == 2)
        #expect(summaries[.codex]?.count == 2)
        #expect(summaries[.claude]?.first?.levels.map(\.level) == [.high])
        #expect(summaries[.codex]?.first?.levels.map(\.level) == [.xhigh])
    }

    private func sample(
        provider: Provider,
        session: String,
        level: EffortLevel?,
        age: TimeInterval,
        subagent: Bool = false
    ) -> EffortUsageSample {
        EffortUsageSample(
            provider: provider,
            sessionID: session,
            effortLevel: level,
            timestamp: now.addingTimeInterval(-age),
            isSubagentSession: subagent
        )
    }
}
