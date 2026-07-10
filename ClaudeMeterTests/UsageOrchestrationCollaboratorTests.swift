//
//  UsageOrchestrationCollaboratorTests.swift
//  ClaudeMeterTests
//

import AppKit
import Foundation
import SwiftData
import Testing
@testable import ClaudeMeter
@testable import ClaudeMeterKit

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

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([TokenLogEntry.self, ImportedFile.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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

    init(update: TokenUsageRefreshUpdate, details: [Provider: ProviderDetail]) {
        self.update = update
        self.details = details
    }

    func refresh(selectedPeriod: UsagePeriod) async throws -> TokenUsageRefreshUpdate {
        update
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
    private let shouldFailParsedEntries: Bool

    init(
        snapshot: TokenUsageSnapshot,
        parsedResults: [URL: TokenUsageService.IncrementalParseResult] = [:],
        extraDetails: [Provider: ProviderDetail] = [:],
        shouldFailParsedEntries: Bool = false
    ) {
        self.snapshot = snapshot
        self.parsedResults = parsedResults
        self.extraDetails = extraDetails
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
}

private enum StubTokenUsageError: Error {
    case failed
}
