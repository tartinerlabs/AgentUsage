import AgentUsageKit
@testable import AgentUsageProviderCore
import Foundation
import Testing

@Suite("Shadow validation")
struct ShadowValidationTests {
    @Test("uses stable IDs and configured tolerances")
    func comparisons() {
        let reset = Date(timeIntervalSince1970: 2_000)
        let lhs = snapshot(utilization: 50, reset: reset)
        let matching = snapshot(utilization: 50.9, reset: reset.addingTimeInterval(119))
        #expect(ShadowComparator.compare(authoritative: lhs, shadow: matching).isEmpty)

        let mismatching = snapshot(utilization: 51.1, reset: reset.addingTimeInterval(121))
        let result = ShadowComparator.compare(authoritative: lhs, shadow: mismatching)
        #expect(result.contains(.utilization))
        #expect(result.contains(.resetTime))
    }

    @Test("persisted diagnostics contain categories but no raw values")
    func redactionByConstruction() throws {
        let entry = ShadowDiagnosticEntry(
            provider: .claude,
            recordedAt: Date(timeIntervalSince1970: 3_600),
            strategyIDs: ["oauth-api"],
            timing: .oneToFiveSeconds,
            mismatches: [.utilization],
            failureCategory: nil
        )
        let encoded = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(encoded.contains("utilization"))
        #expect(!encoded.contains("50.9"))
        #expect(!encoded.lowercased().contains("authorization"))
        #expect(!encoded.lowercased().contains("cookie"))
    }

    private func snapshot(utilization: Double, reset: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: [UsageWindow(
                utilization: utilization,
                resetsAt: reset,
                windowID: "session",
                displayName: "Session",
                totalDuration: 18_000
            )],
            planName: "Pro",
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
