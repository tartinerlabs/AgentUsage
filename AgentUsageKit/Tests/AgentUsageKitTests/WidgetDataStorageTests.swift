import Foundation
import Testing
@testable import AgentUsageKit

@Suite("WidgetDataStorage")
struct WidgetDataStorageTests {
    @Test func providerOnlyPayloadRoundTripsAndRemovesStaleClaudeCache() throws {
        let fixture = try StorageFixture()
        defer { fixture.clear() }
        let legacy = Self.claudeSnapshot()
        #expect(fixture.storage.save(legacy))
        #expect(fixture.storage.load() != nil)

        let codex = Self.providerSnapshot(provider: .codex, windowType: .codexFiveHour)
        #expect(fixture.storage.save([codex]))

        let loaded = fixture.storage.loadProviderSnapshots()
        #expect(loaded.map(\.provider) == [.codex])
        #expect(fixture.storage.load() == nil)
        #expect(fixture.defaults.data(forKey: WidgetDataStorage.snapshotKey) == nil)
    }

    @Test func multipleProvidersAndCustomWindowMetadataRoundTrip() throws {
        let fixture = try StorageFixture()
        defer { fixture.clear() }
        let reset = Date().addingTimeInterval(31 * 24 * 3_600)
        let cursor = ProviderUsageSnapshot(
            provider: .cursor,
            windows: [
                UsageWindow(
                    utilization: 37.5,
                    resetsAt: reset,
                    windowID: "cursor.total",
                    displayName: "Total usage",
                    totalDuration: 31 * 24 * 3_600,
                    scope: UsageWindowScope(model: "auto")
                ),
            ],
            extraUsage: ExtraUsageCost(used: 12, limit: 50, currencyCode: "USD"),
            fetchedAt: Date()
        )
        let claude = ProviderUsageSnapshot(claude: Self.claudeSnapshot())
        let codex = Self.providerSnapshot(provider: .codex, windowType: .codexWeekly)

        // Storage normalizes to Provider.allCases order, independent of input order.
        #expect(fixture.storage.save([cursor, codex, claude]))
        let loaded = fixture.storage.loadProviderSnapshots()

        #expect(loaded.map(\.provider) == [.claude, .codex, .cursor])
        let loadedCursor = try #require(loaded.first { $0.provider == .cursor })
        let window = try #require(loadedCursor.windows.first)
        #expect(window.windowID.rawValue == "cursor.total")
        #expect(window.displayName == "Total usage")
        #expect(window.totalDuration == 31 * 24 * 3_600)
        #expect(window.scope?.model == "auto")
        #expect(loadedCursor.extraUsage?.used == 12)
    }

    @Test func legacyUsageSnapshotLoadsAsClaudeProvider() throws {
        let fixture = try StorageFixture()
        defer { fixture.clear() }
        let legacy = Self.claudeSnapshot()
        fixture.defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: WidgetDataStorage.snapshotKey
        )

        let payload = try #require(fixture.storage.loadPayload())
        #expect(payload.providerSnapshots.map(\.provider) == [.claude])
        #expect(payload.providerSnapshots.first?.windows.map(\.windowID.rawValue) == ["session", "opus"])
    }

    @Test func modernClaudeSnapshotWinsOverLegacyBridge() throws {
        let legacy = Self.claudeSnapshot(sessionUtilization: 10)
        let modern = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                UsageWindow(
                    utilization: 88,
                    resetsAt: Date().addingTimeInterval(3_600),
                    windowType: .session
                ),
            ],
            fetchedAt: Date()
        )

        let payload = WidgetUsagePayload(snapshot: legacy, providerSnapshots: [modern])

        #expect(payload.providerSnapshots.count == 1)
        #expect(payload.snapshot(for: .claude)?.windows.first?.utilization == 88)
    }

    @Test func corruptModernPayloadFallsBackToLegacySnapshot() throws {
        let fixture = try StorageFixture()
        defer { fixture.clear() }
        fixture.defaults.set(Data("not-json".utf8), forKey: WidgetDataStorage.payloadKey)
        fixture.defaults.set(
            try JSONEncoder().encode(Self.claudeSnapshot()),
            forKey: WidgetDataStorage.snapshotKey
        )

        #expect(fixture.storage.loadProviderSnapshots().map(\.provider) == [.claude])
    }

    @Test func clearRemovesModernAndLegacyPayloads() throws {
        let fixture = try StorageFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.save([Self.providerSnapshot(provider: .codex, windowType: .codexFiveHour)]))
        fixture.defaults.set(Data([0x1]), forKey: WidgetDataStorage.snapshotKey)

        fixture.storage.clear()

        #expect(fixture.defaults.data(forKey: WidgetDataStorage.payloadKey) == nil)
        #expect(fixture.defaults.data(forKey: WidgetDataStorage.snapshotKey) == nil)
        #expect(fixture.storage.loadPayload() == nil)
    }

    private static func claudeSnapshot(sessionUtilization: Double = 20) -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            session: UsageWindow(
                utilization: sessionUtilization,
                resetsAt: now.addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 30,
                resetsAt: now.addingTimeInterval(7_200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: now
        )
    }

    private static func providerSnapshot(
        provider: Provider,
        windowType: UsageWindowType
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(
                    utilization: 42,
                    resetsAt: Date().addingTimeInterval(3_600),
                    windowType: windowType
                ),
            ],
            fetchedAt: Date()
        )
    }
}

private struct StorageFixture {
    let suiteName: String
    let defaults: UserDefaults
    let storage: WidgetDataStorage

    init() throws {
        suiteName = "WidgetDataStorageTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        storage = WidgetDataStorage(suiteName: suiteName)
    }

    func clear() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
