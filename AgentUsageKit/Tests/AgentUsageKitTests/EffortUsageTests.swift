import Foundation
import Testing
@testable import AgentUsageKit

@Suite("Effort usage models")
struct EffortUsageTests {
    @Test func effortLevelPreservesUnknownRawValueWhenCodable() throws {
        let level = EffortLevel(rawValue: "super-high")

        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(EffortLevel.self, from: data)

        #expect(String(decoding: data, as: UTF8.self) == "\"super-high\"")
        #expect(decoded == level)
        #expect(decoded.rawValue == "super-high")
        #expect(decoded.displayName == "super-high")
    }

    @Test func effortLevelsUseStablePresentationOrder() {
        let futureLevel = EffortLevel(rawValue: "super-high")
        let unsorted: [EffortLevel] = [
            .mixed,
            .ultra,
            futureLevel,
            .minimal,
            .xhigh,
            .low,
            .max,
            .high,
            .medium,
        ]

        #expect(unsorted.sorted() == [
            .minimal,
            .low,
            .medium,
            .high,
            .xhigh,
            .max,
            .ultra,
            futureLevel,
            .mixed,
        ])
        #expect(EffortLevel.displayOrder == [
            .minimal,
            .low,
            .medium,
            .high,
            .xhigh,
            .max,
            .ultra,
            .mixed,
        ])
    }

    @Test func periodSummaryProvidesCountsFractionsAndLookup() {
        let summary = EffortPeriodSummary(
            period: .last7Days,
            levels: [
                EffortLevelCount(level: .high, sessionCount: 3),
                EffortLevelCount(level: .xhigh, sessionCount: 1),
            ],
            classifiedSessionCount: 4,
            unclassifiedSessionCount: 2
        )

        #expect(summary.totalSessionCount == 6)
        #expect(summary.sessionCount(for: .high) == 3)
        #expect(summary.sessionCount(for: .medium) == 0)
        #expect(summary.levelCount(for: .xhigh)?.sessionCount == 1)
        #expect(summary.fraction(for: .high) == 0.75)
        #expect(EffortPeriod.last7Days.displayName == "7 Days")
    }

    @Test func providerSnapshotRoundTripsEffortSummaries() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let summary = EffortPeriodSummary(
            period: .last30Days,
            levels: [EffortLevelCount(level: .xhigh, sessionCount: 12)],
            classifiedSessionCount: 12,
            unclassifiedSessionCount: 3
        )
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [],
            effortSummaries: [summary],
            fetchedAt: fetchedAt
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.provider == .codex)
        #expect(decoded.fetchedAt == fetchedAt)
        #expect(decoded.effortSummaries == [summary])
        #expect(decoded.effortSummary(for: .last30Days) == summary)
    }

    @Test func claudeSnapshotBridgeAcceptsEffortSummaries() {
        let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let usageSnapshot = UsageSnapshot(
            session: UsageWindow(
                utilization: 10,
                resetsAt: fetchedAt.addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 20,
                resetsAt: fetchedAt.addingTimeInterval(86_400),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: fetchedAt
        )
        let summary = EffortPeriodSummary(
            period: .today,
            levels: [EffortLevelCount(level: .high, sessionCount: 1)],
            classifiedSessionCount: 1,
            unclassifiedSessionCount: 0
        )

        let providerSnapshot = ProviderUsageSnapshot(
            claude: usageSnapshot,
            planName: "Pro",
            effortSummaries: [summary]
        )

        #expect(providerSnapshot.provider == .claude)
        #expect(providerSnapshot.planName == "Pro")
        #expect(providerSnapshot.effortSummaries == [summary])
    }

    @Test func providerSnapshotDecodesLegacyPayloadWithoutEffortSummaries() throws {
        let payload = """
        {
          "provider": "codex",
          "windows": [],
          "fetchedAt": 1000
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let snapshot = try decoder.decode(
            ProviderUsageSnapshot.self,
            from: try #require(payload.data(using: .utf8))
        )

        #expect(snapshot.provider == .codex)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.effortSummaries.isEmpty)
        #expect(snapshot.fetchedAt == Date(timeIntervalSince1970: 1000))
    }
}
