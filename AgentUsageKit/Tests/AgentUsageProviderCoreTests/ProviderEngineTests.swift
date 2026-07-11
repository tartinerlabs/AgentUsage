import AgentUsageKit
import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Provider engine")
struct ProviderEngineTests {
    @Test func preservesLastGoodSnapshotOnFailure() async throws {
        let old = sampleSnapshot(percent: 30)
        let restored = ProviderRuntimeState(
            provider: .codex,
            snapshot: old,
            sourceLabel: "oauth",
            freshness: .fresh,
            generation: 1,
            lastSuccessfulAt: old.fetchedAt
        )
        let descriptor = ProviderDescriptor(
            provider: .codex,
            displayName: "Codex",
            sourceModes: [.automatic],
            pipeline: ProviderFetchPipeline { _ in [FailingStrategy()] }
        )
        let engine = ProviderEngine(descriptors: [descriptor], restoredStates: [.codex: restored])

        await engine.refresh(provider: .codex, context: .init(runtime: .shadow), policy: .replace)
        let state = try #require(await engine.currentStates()[.codex])
        #expect(state.snapshot?.windows.first?.utilization == 30)
        #expect(state.freshness == .stale)
        #expect(state.failureCategory == .network)
    }
}

private struct FailingStrategy: ProviderFetchStrategy {
    let id = "failing"
    let kind = ProviderFetchKind.api
    func isAvailable(in _: ProviderFetchContext) async -> Bool { true }
    func fetch(in _: ProviderFetchContext) async throws -> ProviderFetchResult {
        throw URLError(.networkConnectionLost)
    }
    func shouldFallback(after _: Error, in _: ProviderFetchContext) -> Bool { false }
}

private func sampleSnapshot(percent: Double) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(
        provider: .codex,
        windows: [UsageWindow(
            utilization: percent,
            resetsAt: Date().addingTimeInterval(3600),
            windowType: .codexFiveHour
        )],
        fetchedAt: Date()
    )
}
