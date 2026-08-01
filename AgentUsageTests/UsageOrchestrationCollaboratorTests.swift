//
//  UsageOrchestrationCollaboratorTests.swift
//  AgentUsageTests
//

#if os(macOS)
import AppKit
import Foundation
import SwiftData
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("RefreshScheduler")
struct RefreshSchedulerTests {
    @Test @MainActor func loadsAndPersistsRefreshFrequency() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(RefreshFrequency.twoMinutes.rawValue, forKey: "refreshInterval")
        let scheduler = RefreshScheduler(defaults: testDefaults.defaults)

        #expect(scheduler.refreshInterval == .twoMinutes)

        scheduler.refreshInterval = .manual

        #expect(testDefaults.defaults.string(forKey: "refreshInterval") == "manual")
        scheduler.stopAutoRefresh()
    }
}

@Suite("MenuBarSettingsManager")
struct MenuBarSettingsManagerTests {
    @Test @MainActor func openCodeOfferingsExposeQuotaWindows() {
        let expected: [UsageWindowType] = [
            .openCodeGoFiveHour,
            .openCodeGoWeekly,
            .openCodeGoMonthly,
        ]

        #expect(MenuBarSettingsManager.supportedWindows(for: .openCode) == expected)
        #expect(MenuBarSettingsManager.supportedWindows(for: .openCodeGo) == expected)
        #expect(Provider.openCode.supports(.rateWindows))
    }

    @Test @MainActor func untouchedInstallUsesPrimaryClaudeAndCodexPairs() {
        let testDefaults = TestUserDefaults()
        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(settings.pinnedWindows(for: .claude) == [.session, .opus])
        #expect(settings.pinnedWindows(for: .codex) == [.codexFiveHour, .codexWeekly])
        #expect(testDefaults.defaults.integer(forKey: "menuBarPinnedWindowsSchemaVersion") == 1)
    }

    @Test @MainActor func migratesLegacySelectionsInCanonicalOrderAndCapsAtTwo() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(false, forKey: "menuBarShowSession")
        testDefaults.defaults.set(true, forKey: "menuBarShowAllModels")
        testDefaults.defaults.set(true, forKey: "menuBarShowSonnet")
        testDefaults.defaults.set(true, forKey: "menuBarShowDesign")
        testDefaults.defaults.set(false, forKey: "menuBarShowCodex")

        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(settings.pinnedWindows(for: .claude) == [.opus, .sonnet])
        #expect(settings.pinnedWindows(for: .codex).isEmpty)
    }

    @Test @MainActor func explicitEmptyLegacyClaudeSelectionRetainsSessionFallback() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(false, forKey: "menuBarShowSession")
        testDefaults.defaults.set(false, forKey: "menuBarShowAllModels")
        testDefaults.defaults.set(false, forKey: "menuBarShowSonnet")
        testDefaults.defaults.set(false, forKey: "menuBarShowDesign")
        testDefaults.defaults.set(false, forKey: "menuBarShowFable")

        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(settings.pinnedWindows(for: .claude) == [.session])
    }

    @Test @MainActor func explicitLegacyCodexEnableMigratesBothCodexWindows() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(true, forKey: "menuBarShowCodex")

        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(settings.pinnedWindows(for: .codex) == [.codexFiveHour, .codexWeekly])
    }

    @Test @MainActor func enforcesTwoPinsAndPersistsOrderedChanges() {
        let testDefaults = TestUserDefaults()
        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(!settings.canPin(.sonnet, for: .claude))
        settings.setPinned(.sonnet, for: .claude, isPinned: true)
        #expect(settings.pinnedWindows(for: .claude) == [.session, .opus])

        settings.setPinned(.opus, for: .claude, isPinned: false)
        #expect(settings.canPin(.sonnet, for: .claude))
        settings.setPinned(.sonnet, for: .claude, isPinned: true)
        #expect(settings.pinnedWindows(for: .claude) == [.session, .sonnet])

        let reloaded = MenuBarSettingsManager(defaults: testDefaults.defaults)
        #expect(reloaded.pinnedWindows(for: .claude) == [.session, .sonnet])
    }

    @Test @MainActor func allowsProviderToHaveNoPins() {
        let testDefaults = TestUserDefaults()
        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        settings.setPinned(.codexFiveHour, for: .codex, isPinned: false)
        settings.setPinned(.codexWeekly, for: .codex, isPinned: false)

        #expect(settings.pinnedWindows(for: .codex).isEmpty)
        #expect(MenuBarSettingsManager(defaults: testDefaults.defaults).pinnedWindows(for: .codex).isEmpty)
    }
}

@Suite("MenuBarStatusContent")
struct MenuBarStatusContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test @MainActor func buildsClaudeThenCodexAndHonorsPinOrderAndLimit() {
        let content = MenuBarStatusContentBuilder.build(
            snapshots: [
                .claude: snapshot(
                    provider: .claude,
                    windows: [
                        window(12.4, type: .session),
                        window(15.6, type: .opus),
                        window(99, type: .sonnet),
                    ]
                ),
                .codex: snapshot(
                    provider: .codex,
                    windows: [
                        window(2.1, type: .codexFiveHour),
                        window(0, type: .codexWeekly),
                    ]
                ),
                .openCode: snapshot(
                    provider: .openCode,
                    windows: [window(77, type: .openCodeGoFiveHour)]
                ),
            ],
            pinnedWindows: [
                .claude: [.opus, .session, .sonnet],
                .codex: [.codexFiveHour, .codexWeekly],
                .openCode: [.openCodeGoFiveHour],
            ],
            now: now
        )

        #expect(content.groups.map(\.id) == ["claude", "codex"])
        #expect(content.groups[0].metrics.map(\.id) == ["opus", "session"])
        #expect(content.groups[0].metrics.map(\.percentUsed) == [16, 12])
        #expect(content.groups[1].metrics.map(\.percentUsed) == [2, 0])
    }

    @Test @MainActor func keepsLiveZeroAndOmitsExpiredMissingAndEmptyProviders() {
        let content = MenuBarStatusContentBuilder.build(
            snapshots: [
                .claude: snapshot(
                    provider: .claude,
                    windows: [
                        window(0, type: .session),
                        window(42, type: .opus, isExpired: true),
                    ]
                ),
                .codex: snapshot(provider: .codex, windows: []),
            ],
            pinnedWindows: [
                .claude: [.session, .opus],
                .codex: [.codexWeekly],
            ],
            now: now
        )

        #expect(content.groups.count == 1)
        #expect(content.groups[0].metrics.map(\.percentUsed) == [0])
    }

    @Test @MainActor func unavailableFiveHourPinDoesNotHideWeeklyWindow() {
        let content = MenuBarStatusContentBuilder.build(
            snapshots: [
                .codex: snapshot(
                    provider: .codex,
                    windows: [window(16, type: .codexWeekly)]
                ),
            ],
            pinnedWindows: [
                .codex: [.codexFiveHour, .codexWeekly],
            ],
            now: now
        )

        #expect(content.groups.count == 1)
        #expect(content.groups[0].metrics.map(\.id) == [UsageWindowType.codexWeekly.rawValue])
        #expect(content.groups[0].metrics.map(\.percentUsed) == [16])
    }

    @Test @MainActor func formatsOverLimitUsageAndBuildsVoiceOverSummary() {
        let content = MenuBarStatusContentBuilder.build(
            snapshots: [
                .claude: snapshot(
                    provider: .claude,
                    windows: [window(115.7, type: .session)]
                ),
            ],
            pinnedWindows: [.claude: [.session]],
            now: now
        )

        #expect(content.groups[0].metrics[0].value == "116%")
        #expect(content.accessibilityText == "Claude, Current session 116 percent used")
    }

    @Test @MainActor func returnsEmptyContentWhenNothingIsRenderable() {
        let content = MenuBarStatusContentBuilder.build(
            snapshots: [:],
            pinnedWindows: [.claude: [.session]],
            now: now
        )

        #expect(content.isEmpty)
    }

    @Test @MainActor func rendersTemplateImageWithAccessibilityDescription() throws {
        let content = MenuBarStatusContent(
            groups: [
                .init(
                    id: "claude",
                    displayName: "Claude",
                    metrics: [
                        .init(id: "session", label: "Current session", percentUsed: 12),
                        .init(id: "opus", label: "All models", percentUsed: 15),
                    ]
                ),
            ]
        )

        let image = try #require(MenuBarStatusRenderer.image(for: content, scale: 2))

        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(image.accessibilityDescription == content.accessibilityText)
    }

    private func snapshot(
        provider: Provider,
        windows: [UsageWindow]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(provider: provider, windows: windows, fetchedAt: now)
    }

    private func window(
        _ utilization: Double,
        type: UsageWindowType,
        isExpired: Bool = false
    ) -> UsageWindow {
        UsageWindow(
            utilization: utilization,
            resetsAt: now.addingTimeInterval(isExpired ? -60 : 3_600),
            windowType: type
        )
    }
}

@Suite("TokenUsageCoordinator")
struct TokenUsageCoordinatorTests {
    @Test @MainActor func directServiceFallbackLeavesPeriodCacheUnchanged() async throws {
        let testDefaults = TestUserDefaults()
        let snapshot = Self.makeTokenSnapshot(inputTokens: 12)
        let service = StubTokenUsageService(snapshot: snapshot)
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            defaults: testDefaults.defaults
        )

        let update = try await coordinator.refresh(selectedPeriod: .last30Days)

        #expect(update.snapshot.today.tokens.inputTokens == 12)
        #expect(update.periodSummaries.isEmpty)
        #expect(update.selectedPeriodSummary == nil)
    }

    @Test @MainActor func repositoryPathSeedsVisibleAndSelectedPeriods() async throws {
        let testDefaults = TestUserDefaults()
        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)
        testDefaults.defaults.set(
            fixedDate.timeIntervalSince1970,
            forKey: TokenUsageCoordinator.lastCleanupDateKey
        )
        testDefaults.defaults.set(
            fixedDate.timeIntervalSince1970,
            forKey: TokenUsageCoordinator.lastZeroCostRecalcDateKey
        )
        testDefaults.defaults.set(
            TokenUsageCoordinator.costModelVersion,
            forKey: TokenUsageCoordinator.costModelRepricedVersionKey
        )
        let container = try Self.makeContainer()
        let service = StubTokenUsageService(snapshot: Self.makeTokenSnapshot(inputTokens: 0))
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            modelContext: container.mainContext,
            defaults: testDefaults.defaults,
            now: { fixedDate.addingTimeInterval(60) }
        )

        let update = try await coordinator.refresh(selectedPeriod: .last90Days)

        #expect(update.snapshot.today.tokens.totalTokens == 0)
        #expect(update.periodSummaries[.today]?.period == .today)
        #expect(update.periodSummaries[.last30Days]?.period == .last30Days)
        #expect(update.periodSummaries[.last90Days]?.period == .last90Days)
        #expect(update.selectedPeriodSummary?.period == .last90Days)
        #expect(
            testDefaults.defaults.double(forKey: TokenUsageCoordinator.lastCleanupDateKey)
                == fixedDate.timeIntervalSince1970
        )
        #expect(
            testDefaults.defaults.integer(forKey: TokenUsageCoordinator.costModelRepricedVersionKey)
                == TokenUsageCoordinator.costModelVersion
        )
    }

    @Test @MainActor func parsedEntryFailureMapsToFileReadError() async throws {
        let testDefaults = TestUserDefaults()
        let container = try Self.makeContainer()
        let service = StubTokenUsageService(
            snapshot: Self.makeTokenSnapshot(inputTokens: 0),
            shouldFailParsedEntries: true
        )
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            modelContext: container.mainContext,
            defaults: testDefaults.defaults
        )

        do {
            _ = try await coordinator.refresh(selectedPeriod: .last30Days)
            Issue.record("Expected a file-read error")
        } catch TokenUsageError.fileReadError {
            // Expected mapping.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func failedEffortBackfillPreservesExistingUsageRows() async throws {
        let testDefaults = TestUserDefaults()
        let container = try Self.makeContainer()
        let existing = TokenLogEntry(
            messageId: "existing-message",
            requestId: "existing-request",
            modelName: "claude-opus-4-6",
            inputTokens: 10,
            outputTokens: 2,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            timestamp: Date(),
            costUSD: 0
        )
        container.mainContext.insert(existing)
        try container.mainContext.save()
        let coordinator = TokenUsageCoordinator(
            tokenService: StubTokenUsageService(
                snapshot: Self.makeTokenSnapshot(inputTokens: 0),
                shouldFailParsedEntries: true
            ),
            modelContext: container.mainContext,
            defaults: testDefaults.defaults
        )

        do {
            _ = try await coordinator.refresh(selectedPeriod: .last30Days)
            Issue.record("Expected a file-read error")
        } catch TokenUsageError.fileReadError {
            // Expected mapping.
        }

        let samples = try await TokenUsageQuerier(modelContainer: container)
            .fetchEffortUsageSamples(since: .distantPast)
        #expect(samples.count == 1)
        #expect(samples.first?.sessionID == "existing-message:existing-request")
        #expect(
            testDefaults.defaults.integer(forKey: TokenUsageCoordinator.effortMetadataImportedVersionKey)
                == 0
        )
    }

    @Test @MainActor func malformedJSONLineDoesNotDiscardValidAssistantEntry() async {
        let service = TokenUsageService()
        let content = """
        not-json
        {"type":"assistant","timestamp":"2026-07-12T00:00:00.000Z","requestId":"req-1","message":{"id":"msg-1","model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":2}}}
        {"type":"user","timestamp":"2026-07-12T00:00:01.000Z"}
        """

        let parsed = await service.parseJSONLines(content)

        #expect(parsed.count == 1)
        #expect(parsed.first?.entry.tokens.inputTokens == 10)
        #expect(parsed.first?.entry.tokens.outputTokens == 2)
    }

    @Test @MainActor func claudeParserCapturesAndNormalizesSessionEffortMetadata() async {
        let service = TokenUsageService()
        let content = """
        {"type":"assistant","timestamp":"2026-07-12T00:00:00.000Z","sessionId":"  session-from-log  ","effort":"  HIGH  ","message":{"id":"msg-1","model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":2}}}
        """

        let parsed = await service.parseJSONLines(
            content,
            fallbackSessionID: "session-from-file",
            isSubagentSession: true
        )
        let entry = parsed.first?.entry

        #expect(parsed.count == 1)
        #expect(entry?.sessionID == "session-from-log")
        #expect(entry?.effortLevel?.rawValue == "high")
        #expect(entry?.isSubagentSession == true)
    }

    @Test @MainActor func claudeParserUsesFileSessionFallbackAndLeavesMissingEffortNil() async {
        let service = TokenUsageService()
        let content = """
        {"type":"assistant","timestamp":"2026-07-12T00:00:00.000Z","message":{"id":"msg-1","model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":2}}}
        """

        let entry = await service.parseJSONLines(
            content,
            fallbackSessionID: "file-session-id"
        ).first?.entry

        #expect(entry?.sessionID == "file-session-id")
        #expect(entry?.effortLevel == nil)
        #expect(entry?.isSubagentSession == false)
    }

    @Test @MainActor func importerPersistsEffortSessionAndSubagentMetadata() async throws {
        let container = try Self.makeContainer()
        let repository = TokenUsageRepository(modelContext: container.mainContext)
        let entry = UsageEntry(
            model: "claude-opus-4-6",
            tokens: TokenCount(
                inputTokens: 10,
                outputTokens: 2,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            ),
            timestamp: Date(timeIntervalSince1970: 1_752_969_600),
            sessionID: "session-persisted",
            effortLevel: EffortLevel(rawValue: "medium"),
            isSubagentSession: true
        )

        try await repository.importEntries(
            [(entry: entry, messageId: "msg-persisted", requestId: "req-persisted")],
            forFile: URL(fileURLWithPath: "/tmp/session-persisted.jsonl"),
            newByteOffset: 100,
            newFileSize: 100,
            newModified: entry.timestamp
        )

        let stored = try #require(container.mainContext.fetch(FetchDescriptor<TokenLogEntry>()).first)
        #expect(stored.sessionID == "session-persisted")
        #expect(stored.effortLevelRaw == "medium")
        #expect(stored.effortLevel?.rawValue == "medium")
        #expect(stored.isSubagentSession == true)
    }

    @Test @MainActor func firstEffortRefreshBackfillsLegacyRowsAndMarksComplete() async throws {
        let testDefaults = TestUserDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let container = try Self.makeContainer()
        let legacy = TokenLogEntry(
            messageId: "rebuilt-message",
            requestId: "rebuilt-request",
            modelName: "claude-opus-4-6",
            inputTokens: 10,
            outputTokens: 2,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            timestamp: now.addingTimeInterval(-300),
            costUSD: 0
        )
        container.mainContext.insert(legacy)
        try container.mainContext.save()

        let rebuiltEntry = UsageEntry(
            model: "claude-opus-4-6",
            tokens: TokenCount(
                inputTokens: 10,
                outputTokens: 2,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            ),
            timestamp: now.addingTimeInterval(-60),
            sessionID: "rebuilt-session",
            effortLevel: .high
        )
        let fileURL = URL(fileURLWithPath: "/tmp/rebuilt-session.jsonl")
        let service = StubTokenUsageService(
            snapshot: Self.makeTokenSnapshot(inputTokens: 0),
            parsedResults: [
                fileURL: TokenUsageService.IncrementalParseResult(
                    entries: [(
                        entry: rebuiltEntry,
                        messageId: "rebuilt-message",
                        requestId: "rebuilt-request"
                    )],
                    newByteOffset: 100,
                    newFileSize: 100,
                    newModified: now
                ),
            ]
        )
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            modelContext: container.mainContext,
            defaults: testDefaults.defaults,
            now: { now }
        )

        _ = try await coordinator.refresh(selectedPeriod: .last30Days)
        let samples = try await TokenUsageQuerier(modelContainer: container)
            .fetchEffortUsageSamples(since: now.addingTimeInterval(-3_600))

        #expect(samples.count == 1)
        #expect(samples.first?.sessionID == "rebuilt-session")
        #expect(samples.first?.effortLevel == .high)
        #expect(
            testDefaults.defaults.integer(forKey: TokenUsageCoordinator.effortMetadataImportedVersionKey)
                == TokenUsageCoordinator.effortMetadataVersion
        )
    }

    @Test @MainActor func maintenancePersistsDailyGatesAndCostModelVersion() async throws {
        let testDefaults = TestUserDefaults()
        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)
        let container = try Self.makeContainer()
        let service = StubTokenUsageService(snapshot: Self.makeTokenSnapshot(inputTokens: 0))
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            modelContext: container.mainContext,
            defaults: testDefaults.defaults,
            now: { fixedDate }
        )

        _ = try await coordinator.refresh(selectedPeriod: .today)

        #expect(
            testDefaults.defaults.double(forKey: TokenUsageCoordinator.lastCleanupDateKey)
                == fixedDate.timeIntervalSince1970
        )
        #expect(
            testDefaults.defaults.double(forKey: TokenUsageCoordinator.lastZeroCostRecalcDateKey)
                == fixedDate.timeIntervalSince1970
        )
        #expect(
            testDefaults.defaults.integer(forKey: TokenUsageCoordinator.costModelRepricedVersionKey)
                == TokenUsageCoordinator.costModelVersion
        )
    }

    @Test @MainActor func providerDetailsCombineExtraProvidersAndClaude() async {
        let testDefaults = TestUserDefaults()
        let codexDetail = Self.makeProviderDetail(inputTokens: 40, costUSD: 2.5)
        let service = StubTokenUsageService(
            snapshot: Self.makeTokenSnapshot(inputTokens: 0),
            extraDetails: [.codex: codexDetail]
        )
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            defaults: testDefaults.defaults
        )

        let details = await coordinator.providerDetails(
            using: Self.makeTokenSnapshot(inputTokens: 25)
        )

        #expect(details[.codex]?.today.tokens.inputTokens == 40)
        #expect(details[.claude]?.today.tokens.inputTokens == 25)
        #expect(details[.claude]?.yesterday.tokens.totalTokens == 0)
        #expect(details[.claude]?.dailyCosts == [])
    }

    @Test @MainActor func providerDetailsAttachEffortFromNormalProviderRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            EffortUsageSample(
                provider: .codex,
                sessionID: "codex-cross-boundary",
                effortLevel: .xhigh,
                timestamp: now.addingTimeInterval(-60)
            ),
            EffortUsageSample(
                provider: .codex,
                sessionID: "codex-cross-boundary",
                effortLevel: .high,
                timestamp: now.addingTimeInterval(-370 * 24 * 60 * 60)
            ),
            EffortUsageSample(
                provider: .codex,
                sessionID: "codex-cross-boundary",
                effortLevel: .high,
                timestamp: now.addingTimeInterval(-369 * 24 * 60 * 60)
            ),
            EffortUsageSample(
                provider: .codex,
                sessionID: "codex-unclassified",
                effortLevel: nil,
                timestamp: now.addingTimeInterval(-120)
            ),
        ]
        let service = StubTokenUsageService(
            snapshot: Self.makeTokenSnapshot(inputTokens: 0),
            extraEffortSamples: samples
        )
        let coordinator = TokenUsageCoordinator(
            tokenService: service,
            defaults: TestUserDefaults().defaults,
            now: { now }
        )

        let details = await coordinator.providerDetails(using: nil)
        let summary = try #require(details[.codex]?.effortSummary(for: .last30Days))

        #expect(summary.sessionCount(for: .high) == 1)
        #expect(summary.sessionCount(for: .xhigh) == 0)
        #expect(summary.classifiedSessionCount == 1)
        #expect(summary.unclassifiedSessionCount == 1)
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([TokenLogEntry.self, ImportedFile.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    fileprivate static func makeTokenSnapshot(inputTokens: Int) -> TokenUsageSnapshot {
        let today = TokenUsageSummary(
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            ),
            costUSD: 0,
            period: .today
        )
        return TokenUsageSnapshot(
            today: today,
            last30Days: TokenUsageSummary(
                tokens: today.tokens,
                costUSD: today.costUSD,
                period: .last30Days
            ),
            byModel: [:],
            fetchedAt: Date()
        )
    }

    fileprivate static func makeProviderDetail(inputTokens: Int, costUSD: Double) -> ProviderDetail {
        let today = TokenUsageSummary(
            tokens: TokenCount(
                inputTokens: inputTokens,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            ),
            costUSD: costUSD,
            period: .today
        )
        return ProviderDetail(
            today: today,
            yesterday: today,
            last30Days: TokenUsageSummary(
                tokens: today.tokens,
                costUSD: costUSD,
                period: .last30Days
            ),
            byModel: [:],
            dailyCosts: []
        )
    }
}

@Suite("UsageViewModel token coordination")
struct UsageViewModelTokenCoordinationTests {
    @Test @MainActor func appliesCoordinatorUpdatesAndProviderDetails() async {
        let testDefaults = TestUserDefaults()
        let tokenSnapshot = TokenUsageCoordinatorTests.makeTokenSnapshot(inputTokens: 25)
        let selectedSummary = tokenSnapshot.last30Days
        let codexDetail = TokenUsageCoordinatorTests.makeProviderDetail(inputTokens: 40, costUSD: 2.5)
        let coordinator = StubTokenUsageCoordinator(
            update: TokenUsageRefreshUpdate(
                snapshot: tokenSnapshot,
                periodSummaries: [
                    .today: tokenSnapshot.today,
                    .last30Days: tokenSnapshot.last30Days,
                ],
                selectedPeriodSummary: selectedSummary
            ),
            details: [.codex: codexDetail]
        )
        let credentials = MockCredentialProvider()
        await credentials.configure(credentials: MockCredentialProvider.validCredentials())
        let apiService = MockAPIService()
        await apiService.setMockSnapshot(Self.makeUsageSnapshot())
        let viewModel = UsageViewModel(
            credentialProvider: credentials,
            apiService: apiService,
            tokenUsageCoordinator: coordinator,
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        await viewModel.refresh(force: true)

        #expect(viewModel.tokenSnapshot?.today.tokens.inputTokens == 25)
        #expect(viewModel.periodSummaries[.today]?.tokens.inputTokens == 25)
        #expect(viewModel.selectedPeriodSummary?.period == .last30Days)
        #expect(viewModel.providerDetails[.codex]?.today.tokens.inputTokens == 40)
        #expect(viewModel.tokenUsageError == nil)
    }

    @Test @MainActor func failureClearsLoadingAndSuccessfulRetryRestoresTokenSnapshot() async {
        let testDefaults = TestUserDefaults()
        let tokenSnapshot = TokenUsageCoordinatorTests.makeTokenSnapshot(inputTokens: 25)
        let coordinator = StubTokenUsageCoordinator(
            update: TokenUsageRefreshUpdate(
                snapshot: tokenSnapshot,
                periodSummaries: [.today: tokenSnapshot.today],
                selectedPeriodSummary: tokenSnapshot.today
            ),
            details: [:],
            refreshError: TokenUsageError.fileReadError(
                NSError(domain: "TokenUsageTests", code: 1)
            )
        )
        let credentials = MockCredentialProvider()
        await credentials.configure(credentials: MockCredentialProvider.validCredentials())
        let apiService = MockAPIService()
        await apiService.setMockSnapshot(Self.makeUsageSnapshot())
        let viewModel = UsageViewModel(
            credentialProvider: credentials,
            apiService: apiService,
            tokenUsageCoordinator: coordinator,
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        await viewModel.refresh(force: true)

        #expect(viewModel.tokenSnapshot == nil)
        #expect(viewModel.tokenUsageError != nil)
        #expect(!viewModel.isLoadingTokenUsage)

        coordinator.refreshError = nil
        await viewModel.refresh(force: true)

        #expect(viewModel.tokenSnapshot?.today.tokens.inputTokens == 25)
        #expect(viewModel.tokenUsageError == nil)
        #expect(!viewModel.isLoadingTokenUsage)
    }

    @Test @MainActor func enrichedEffortPayloadSurvivesMacRelaunch() async {
        let testDefaults = TestUserDefaults()
        let tokenSnapshot = TokenUsageCoordinatorTests.makeTokenSnapshot(inputTokens: 25)
        let effortSummary = EffortPeriodSummary(
            period: .last30Days,
            levels: [EffortLevelCount(level: .xhigh, sessionCount: 5)],
            classifiedSessionCount: 5,
            unclassifiedSessionCount: 1
        )
        let baseDetail = TokenUsageCoordinatorTests.makeProviderDetail(inputTokens: 40, costUSD: 2.5)
        let codexDetail = ProviderDetail(
            today: baseDetail.today,
            yesterday: baseDetail.yesterday,
            last30Days: baseDetail.last30Days,
            byModel: baseDetail.byModel,
            dailyCosts: baseDetail.dailyCosts,
            effortSummaries: [effortSummary]
        )
        let coordinator = StubTokenUsageCoordinator(
            update: TokenUsageRefreshUpdate(
                snapshot: tokenSnapshot,
                periodSummaries: [.today: tokenSnapshot.today, .last30Days: tokenSnapshot.last30Days],
                selectedPeriodSummary: tokenSnapshot.last30Days
            ),
            details: [.codex: codexDetail]
        )
        let credentials = MockCredentialProvider()
        await credentials.configure(credentials: MockCredentialProvider.validCredentials())
        let apiService = MockAPIService()
        await apiService.setMockSnapshot(Self.makeUsageSnapshot())
        let viewModel = UsageViewModel(
            credentialProvider: credentials,
            apiService: apiService,
            tokenUsageCoordinator: coordinator,
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        await viewModel.refresh(force: true)

        let relaunched = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            tokenUsageCoordinator: coordinator,
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )
        #expect(relaunched.effortSummary(for: .codex, period: .last30Days) == effortSummary)
        #expect(relaunched.providerDetails[.codex]?.effortSummaries == [effortSummary])
    }

    private static func makeUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: 10,
                resetsAt: Date().addingTimeInterval(3_600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 20,
                resetsAt: Date().addingTimeInterval(7_200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )
    }
}

@MainActor
private final class StubTokenUsageCoordinator: TokenUsageCoordinating {
    private let update: TokenUsageRefreshUpdate
    private let details: [Provider: ProviderDetail]
    var refreshError: Error?

    init(
        update: TokenUsageRefreshUpdate,
        details: [Provider: ProviderDetail],
        refreshError: Error? = nil
    ) {
        self.update = update
        self.details = details
        self.refreshError = refreshError
    }

    func refresh(selectedPeriod: UsagePeriod) async throws -> TokenUsageRefreshUpdate {
        if let refreshError { throw refreshError }
        return update
    }

    func summary(for period: UsagePeriod) async throws -> TokenUsageSummary {
        if let summary = update.periodSummaries[period] {
            return summary
        }
        throw TokenUsageError.repositoryUnavailable
    }

    func providerDetails(using snapshot: TokenUsageSnapshot?) async -> [Provider: ProviderDetail] {
        details
    }
}

private actor StubTokenUsageService: TokenUsageServiceProtocol {
    private let snapshot: TokenUsageSnapshot
    private let parsedResults: [URL: TokenUsageService.IncrementalParseResult]
    private let extraDetails: [Provider: ProviderDetail]
    private let extraEffortSamples: [EffortUsageSample]
    private let shouldFailParsedEntries: Bool

    init(
        snapshot: TokenUsageSnapshot,
        parsedResults: [URL: TokenUsageService.IncrementalParseResult] = [:],
        extraDetails: [Provider: ProviderDetail] = [:],
        extraEffortSamples: [EffortUsageSample] = [],
        shouldFailParsedEntries: Bool = false
    ) {
        self.snapshot = snapshot
        self.parsedResults = parsedResults
        self.extraDetails = extraDetails
        self.extraEffortSamples = extraEffortSamples
        self.shouldFailParsedEntries = shouldFailParsedEntries
    }

    func fetchUsage() async throws -> TokenUsageSnapshot {
        snapshot
    }

    func fetchParsedEntries(
        fileStates: [String: TokenUsageService.FileState]
    ) async throws -> [URL: TokenUsageService.IncrementalParseResult] {
        if shouldFailParsedEntries {
            throw StubTokenUsageError.failed
        }
        return parsedResults
    }

    func fetchExtraProviderDetails(since: Date) async -> [Provider: ProviderDetail] {
        extraDetails
    }

    func fetchExtraProviderEffortSamples(since: Date) async -> [EffortUsageSample] {
        extraEffortSamples.filter { $0.timestamp >= since }
    }
}

private enum StubTokenUsageError: Error {
    case failed
}
#endif
