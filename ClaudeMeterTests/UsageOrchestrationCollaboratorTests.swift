//
//  UsageOrchestrationCollaboratorTests.swift
//  ClaudeMeterTests
//

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
    @Test @MainActor func usesExistingDefaults() {
        let testDefaults = TestUserDefaults()
        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        #expect(settings.menuBarShowSession)
        #expect(!settings.menuBarShowAllModels)
        #expect(!settings.menuBarShowSonnet)
        #expect(!settings.menuBarShowDesign)
        #expect(!settings.menuBarShowFable)
        #expect(!settings.menuBarShowCodex)
        #expect(settings.menuBarShowExtraUsage)
    }

    @Test @MainActor func persistsEveryMenuBarSetting() {
        let testDefaults = TestUserDefaults()
        let settings = MenuBarSettingsManager(defaults: testDefaults.defaults)

        settings.menuBarShowSession = false
        settings.menuBarShowAllModels = true
        settings.menuBarShowSonnet = true
        settings.menuBarShowDesign = true
        settings.menuBarShowFable = true
        settings.menuBarShowCodex = true
        settings.menuBarShowExtraUsage = false

        #expect(!testDefaults.defaults.bool(forKey: "menuBarShowSession"))
        #expect(testDefaults.defaults.bool(forKey: "menuBarShowAllModels"))
        #expect(testDefaults.defaults.bool(forKey: "menuBarShowSonnet"))
        #expect(testDefaults.defaults.bool(forKey: "menuBarShowDesign"))
        #expect(testDefaults.defaults.bool(forKey: "menuBarShowFable"))
        #expect(testDefaults.defaults.bool(forKey: "menuBarShowCodex"))
        #expect(!testDefaults.defaults.bool(forKey: "menuBarShowExtraUsage"))
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
