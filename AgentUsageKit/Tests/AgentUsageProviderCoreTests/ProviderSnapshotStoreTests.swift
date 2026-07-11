import AgentUsageKit
import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Provider snapshot persistence")
struct ProviderSnapshotStoreTests {
    @Test func roundTripsAllProviderStates() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("provider-snapshots-v2.json")
        let store = ProviderSnapshotStore(fileURL: url)
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(
                utilization: 42,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .codexFiveHour
            )],
            fetchedAt: Date()
        )
        let envelope = ProviderSnapshotEnvelope(states: [
            ProviderRuntimeState(
                provider: .codex,
                snapshot: snapshot,
                sourceLabel: "oauth",
                freshness: .fresh,
                generation: 3,
                lastSuccessfulAt: snapshot.fetchedAt
            )
        ])

        try await store.save(envelope)
        let loaded = try #require(await store.load())
        #expect(loaded.statesByProvider[.codex]?.snapshot?.windows.first?.utilization == 42)
        #expect(loaded.statesByProvider[.codex]?.sourceLabel == "oauth")
    }

    @Test func migratesLegacyClaudeCacheOnce() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("provider-snapshots-v2.json")
        let store = ProviderSnapshotStore(fileURL: url)
        let legacy = UsageSnapshot(
            session: UsageWindow(
                utilization: 10,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 20,
                resetsAt: Date().addingTimeInterval(7200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )

        let migrated = try #require(await store.loadOrMigrate(
            legacyClaudeSnapshot: legacy,
            legacyPlanName: "Max"
        ))
        #expect(migrated.statesByProvider[.claude]?.snapshot?.planName == "Max")
        #expect(try await store.load() != nil)
    }
}

@Suite("Generic usage windows")
struct GenericUsageWindowTests {
    @Test func customWindowRoundTripsWithoutLosingMetadata() throws {
        let window = UsageWindow(
            utilization: 12.5,
            resetsAt: Date().addingTimeInterval(1000),
            windowID: "weekly:model:fable-next",
            displayName: "Fable Next",
            totalDuration: 7 * 24 * 60 * 60,
            scope: UsageWindowScope(model: "Fable Next")
        )
        let decoded = try JSONDecoder().decode(
            UsageWindow.self,
            from: JSONEncoder().encode(window)
        )
        #expect(decoded.windowID.rawValue == "weekly:model:fable-next")
        #expect(decoded.displayName == "Fable Next")
        #expect(decoded.scope?.model == "Fable Next")
        #expect(decoded.windowType == .custom)
    }
}
