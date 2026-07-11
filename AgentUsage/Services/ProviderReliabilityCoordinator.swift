// Provider refresh orchestration derived in part from steipete/CodexBar.
// Upstream commit: 98de97833505a6213ec2cf3c2c6d528443b77d8d (MIT).
// Original concepts: Sources/CodexBarCore/Providers and Usage/UsageStore.swift.

#if os(macOS)
import AgentUsageKit
import AgentUsageProviderCore
import Foundation

/// Runs the new provider engine without making it display-authoritative. The
/// legacy view-model remains the source of UI data until the dogfood gates pass.
actor ProviderReliabilityCoordinator {
    private static let shadowInterval: TimeInterval = 15 * 60

    private let descriptors: [ProviderDescriptor]
    private let snapshotStore: ProviderSnapshotStore
    private let diagnosticStore: ShadowDiagnosticStore
    private let statusMonitor = ProviderStatusMonitor()
    private let legacySnapshot: UsageSnapshot?
    private let legacyPlanName: String?
    private var engine: ProviderEngine?
    private var lastShadowFetch: [Provider: Date] = [:]

    init(
        credentialProvider: any CredentialProvider,
        claudeService: any APIServiceProtocol,
        providerServices: [Provider: any ProviderUsageServiceProtocol],
        legacySnapshot: UsageSnapshot?,
        legacyPlanName: String?
    ) {
        let claudeStrategy = AnyProviderFetchStrategy(
            id: "claude.oauth-usage-api",
            kind: .oauth,
            fetch: { _ in
                let credentials = try await credentialProvider.loadCredentials()
                let snapshot = try await claudeService.fetchUsage(token: credentials.accessToken)
                return ProviderFetchResult(
                    snapshot: ProviderUsageSnapshot(
                        claude: snapshot,
                        planName: credentials.planDisplayName
                    ),
                    sourceLabel: "OAuth usage API",
                    strategyID: "claude.oauth-usage-api",
                    strategyKind: .oauth
                )
            },
            classify: Self.classify
        )
        let claudeDescriptor = ProviderDescriptor(
            provider: .claude,
            displayName: Provider.claude.displayName,
            statusURL: URL(string: "https://status.anthropic.com/api/v2/status.json"),
            sourceModes: [.automatic, .oauth, .cli, .manualWeb],
            pipeline: ProviderFetchPipeline { _ in [claudeStrategy] }
        )

        var descriptors = [claudeDescriptor]
        if let codexService = providerServices[.codex] {
            let codexStrategy = AnyProviderFetchStrategy(
                id: "codex.oauth-live-usage-api",
                kind: .oauth,
                fetch: { _ in
                    guard let snapshot = try await codexService.fetchSnapshot() else {
                        throw ProviderFetchFailure(category: .unavailable)
                    }
                    return ProviderFetchResult(
                        snapshot: snapshot,
                        sourceLabel: "OAuth live usage API",
                        strategyID: "codex.oauth-live-usage-api",
                        strategyKind: .oauth
                    )
                },
                classify: Self.classify
            )
            descriptors.append(ProviderDescriptor(
                provider: .codex,
                displayName: Provider.codex.displayName,
                statusURL: URL(string: "https://status.openai.com/api/v2/status.json"),
                sourceModes: [.automatic, .oauth, .cli],
                pipeline: ProviderFetchPipeline { _ in [codexStrategy] }
            ))
        }
        self.descriptors = descriptors
        self.legacySnapshot = legacySnapshot
        self.legacyPlanName = legacyPlanName

        let root = Self.applicationSupportDirectory()
            .appendingPathComponent("ProviderReliability", isDirectory: true)
        self.snapshotStore = ProviderSnapshotStore(fileURL: root.appendingPathComponent("snapshots-v2.json"))
        self.diagnosticStore = ShadowDiagnosticStore(fileURL: root.appendingPathComponent("shadow-diagnostics.json"))
    }

    func validate(
        authoritative: [Provider: ProviderUsageSnapshot],
        policy: ProviderRefreshPolicy,
        now: Date = Date()
    ) async {
        var eligible = Set<Provider>()
        for provider in authoritative.keys where descriptors.contains(where: { $0.provider == provider }) {
            if let last = lastShadowFetch[provider], now.timeIntervalSince(last) < Self.shadowInterval { continue }
            lastShadowFetch[provider] = now
            eligible.insert(provider)
        }
        guard !eligible.isEmpty else { return }

        let engine = await resolvedEngine()
        let started = ContinuousClock.now
        await engine.refresh(
            providers: eligible,
            context: ProviderFetchContext(runtime: .shadow),
            policy: policy
        )
        let duration = started.duration(to: .now)
        let states = await engine.currentStates(at: now)

        for provider in eligible {
            guard let reference = authoritative[provider], let state = states[provider] else { continue }
            let attempts = state.attempts.map(\.strategyID)
            let mismatches = state.snapshot.map {
                ShadowComparator.compare(
                    authoritative: reference,
                    shadow: $0,
                    authoritativeSource: "legacy",
                    shadowSource: state.sourceLabel
                )
            } ?? []
            let entry = ShadowDiagnosticEntry(
                provider: provider,
                recordedAt: now,
                strategyIDs: attempts,
                timing: ShadowTimingBucket(duration: duration),
                mismatches: mismatches,
                failureCategory: state.failureCategory
            )
            try? await diagnosticStore.append(entry)
        }
        try? await snapshotStore.save(ProviderSnapshotEnvelope(states: Array(states.values)))
        for descriptor in descriptors where eligible.contains(descriptor.provider) {
            guard let statusURL = descriptor.statusURL else { continue }
            _ = await statusMonitor.status(for: descriptor.provider, url: statusURL, now: now)
        }
    }

    func exportDiagnostics(to destination: URL) async throws {
        try await diagnosticStore.export(to: destination)
    }

    private func resolvedEngine() async -> ProviderEngine {
        if let engine { return engine }
        let restored = try? await snapshotStore.loadOrMigrate(
            legacyClaudeSnapshot: legacySnapshot,
            legacyPlanName: legacyPlanName
        )
        let created = ProviderEngine(
            descriptors: descriptors,
            restoredStates: restored?.statesByProvider ?? [:]
        )
        engine = created
        return created
    }

    private nonisolated static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AgentUsage", isDirectory: true)
    }

    private nonisolated static func classify(_ error: Error) -> ProviderFailureCategory {
        if error is CancellationError { return .cancelled }
        if error is CredentialError { return .authentication }
        if let failure = error as? ProviderFetchFailure { return failure.category }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timedOut : .network
        }
        return .unknown
    }
}
#endif
