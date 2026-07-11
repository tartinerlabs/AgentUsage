import AgentUsageKit
import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Provider fetch pipeline")
struct ProviderFetchPlanTests {
    @Test func fallsBackAndRecordsAttempts() async throws {
        let snapshot = sampleSnapshot(provider: .codex)
        let first = StubStrategy(
            id: "oauth",
            kind: .oauth,
            available: true,
            result: .failure(ProviderFetchFailure(category: .authentication)),
            fallback: true
        )
        let second = StubStrategy(
            id: "cli",
            kind: .cli,
            available: true,
            result: .success(.init(
                snapshot: snapshot,
                sourceLabel: "codex-cli",
                strategyID: "cli",
                strategyKind: .cli
            )),
            fallback: false
        )
        let pipeline = ProviderFetchPipeline { _ in [first, second] }

        let outcome = await pipeline.fetch(
            provider: .codex,
            context: .init(runtime: .shadow)
        )

        let result = try outcome.result.get()
        #expect(result.sourceLabel == "codex-cli")
        #expect(outcome.attempts.count == 2)
        #expect(outcome.attempts[0].failureCategory == .authentication)
    }

    @Test func skipsUnavailableStrategies() async throws {
        let strategy = StubStrategy(
            id: "missing",
            kind: .local,
            available: false,
            result: .failure(ProviderFetchFailure(category: .unknown)),
            fallback: false
        )
        let outcome = await ProviderFetchPipeline { _ in [strategy] }.fetch(
            provider: .claude,
            context: .init(runtime: .shadow)
        )
        #expect(outcome.attempts == [
            .init(strategyID: "missing", kind: .local, wasAvailable: false, failureCategory: nil)
        ])
        #expect(throws: ProviderFetchFailure.self) { try outcome.result.get() }
    }
}

private struct StubStrategy: ProviderFetchStrategy {
    let id: String
    let kind: ProviderFetchKind
    let available: Bool
    let result: Result<ProviderFetchResult, ProviderFetchFailure>
    let fallback: Bool

    func isAvailable(in _: ProviderFetchContext) async -> Bool { available }
    func fetch(in _: ProviderFetchContext) async throws -> ProviderFetchResult { try result.get() }
    func shouldFallback(after _: Error, in _: ProviderFetchContext) -> Bool { fallback }
}

private func sampleSnapshot(provider: Provider) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(
        provider: provider,
        windows: [UsageWindow(
            utilization: 20,
            resetsAt: Date().addingTimeInterval(3600),
            windowType: provider == .codex ? .codexFiveHour : .session
        )],
        fetchedAt: Date()
    )
}
