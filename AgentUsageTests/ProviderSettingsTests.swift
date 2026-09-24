//
//  ProviderSettingsTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
@testable import AgentUsage
@testable import AgentUsageKit

@Suite("ProviderSettings")
struct ProviderSettingsTests {
    @Test func shippedProvidersLeaveOutUnshippedOnes() {
        #expect(ProviderSettings.unshippedProviders == [.openCode, .openCodeGo])
        #expect(ProviderSettings.shippedProviders == [.claude, .codex, .cursor, .grok])
        #expect(ProviderSettings.shippedProviderNames == "Claude, Codex, Cursor, and Grok")
    }

    @Test func displayListJoinsNamesAsEnglishList() {
        #expect(ProviderSettings.displayList([]) == "")
        #expect(ProviderSettings.displayList([.claude]) == "Claude")
        #expect(ProviderSettings.displayList([.claude, .grok]) == "Claude and Grok")
        #expect(ProviderSettings.displayList([.claude, .codex, .grok]) == "Claude, Codex, and Grok")
    }

    @Test func everyShippedProviderIsEnabledByDefault() {
        let testDefaults = TestUserDefaults()

        #expect(ProviderSettings.userDisabledProviders(defaults: testDefaults.defaults).isEmpty)
        for provider in ProviderSettings.shippedProviders {
            #expect(ProviderSettings.isEnabled(provider, defaults: testDefaults.defaults))
        }
        #expect(!ProviderSettings.isEnabled(.openCode, defaults: testDefaults.defaults))
        #expect(!ProviderSettings.isEnabled(.openCodeGo, defaults: testDefaults.defaults))
    }

    @Test func persistsDisabledProvidersAsRawValues() {
        let testDefaults = TestUserDefaults()

        ProviderSettings.setEnabled(false, for: .grok, defaults: testDefaults.defaults)
        ProviderSettings.setEnabled(false, for: .codex, defaults: testDefaults.defaults)

        #expect(
            testDefaults.defaults.stringArray(forKey: Constants.disabledProvidersKey)
                == ["codex", "grok"]
        )
        #expect(ProviderSettings.userDisabledProviders(defaults: testDefaults.defaults) == [.codex, .grok])
        #expect(!ProviderSettings.isEnabled(.codex, defaults: testDefaults.defaults))
        #expect(ProviderSettings.isEnabled(.claude, defaults: testDefaults.defaults))

        ProviderSettings.setEnabled(true, for: .codex, defaults: testDefaults.defaults)

        #expect(testDefaults.defaults.stringArray(forKey: Constants.disabledProvidersKey) == ["grok"])
        #expect(ProviderSettings.enabledCheck(defaults: testDefaults.defaults)(.codex))
        #expect(!ProviderSettings.enabledCheck(defaults: testDefaults.defaults)(.grok))
    }

    @Test func refusesToDisableTheLastEnabledProvider() {
        let testDefaults = TestUserDefaults()
        for provider in [Provider.claude, .codex, .cursor] {
            ProviderSettings.setEnabled(false, for: provider, defaults: testDefaults.defaults)
        }
        let disabled = ProviderSettings.userDisabledProviders(defaults: testDefaults.defaults)

        #expect(!ProviderSettings.canDisable(.grok, userDisabled: disabled))
        let result = ProviderSettings.setEnabled(false, for: .grok, defaults: testDefaults.defaults)

        #expect(result == [.claude, .codex, .cursor])
        #expect(ProviderSettings.isEnabled(.grok, defaults: testDefaults.defaults))
    }

    @Test func storedValueDisablingEverythingIsIgnored() {
        let testDefaults = TestUserDefaults()
        testDefaults.defaults.set(
            ["claude", "codex", "cursor", "grok", "unknown"],
            forKey: Constants.disabledProvidersKey
        )

        #expect(ProviderSettings.userDisabledProviders(defaults: testDefaults.defaults).isEmpty)
    }

    @Test func unshippedProvidersCannotBeToggled() {
        let testDefaults = TestUserDefaults()

        ProviderSettings.setEnabled(true, for: .openCode, defaults: testDefaults.defaults)
        ProviderSettings.setEnabled(false, for: .openCodeGo, defaults: testDefaults.defaults)

        #expect(testDefaults.defaults.stringArray(forKey: Constants.disabledProvidersKey) == nil)
        #expect(!ProviderSettings.isEnabled(.openCode, defaults: testDefaults.defaults))
        #expect(!ProviderSettings.canDisable(.openCodeGo, userDisabled: []))
    }
}

#if os(macOS)
@Suite("UsageViewModel provider settings")
struct UsageViewModelProviderSettingsTests {
    @Test @MainActor func disabledProviderIsNeverFetchedOrShown() async {
        let testDefaults = TestUserDefaults()
        ProviderSettings.setEnabled(false, for: .codex, defaults: testDefaults.defaults)
        let credentials = MockCredentialProvider()
        await credentials.configure(credentials: MockCredentialProvider.validCredentials())
        let apiService = MockAPIService()
        await apiService.setMockSnapshot(Self.makeUsageSnapshot())
        let codex = CountingProviderUsageService(provider: .codex)
        let cursor = CountingProviderUsageService(provider: .cursor)
        let viewModel = UsageViewModel(
            credentialProvider: credentials,
            apiService: apiService,
            providerUsageServices: [.codex: codex, .cursor: cursor],
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        await viewModel.refresh(force: true)

        #expect(await codex.fetchCount == 0)
        #expect(await cursor.fetchCount == 1)
        #expect(viewModel.usageSnapshot(for: .codex) == nil)
        #expect(viewModel.providerDetail(for: .codex) == nil)
        #expect(!viewModel.availableProviders.contains(.codex))
        #expect(viewModel.availableProviders.contains(.claude))
        #expect(viewModel.availableProviders.contains(.cursor))
    }

    @Test @MainActor func disabledClaudeSkipsCredentialsAndAPI() async {
        let testDefaults = TestUserDefaults()
        ProviderSettings.setEnabled(false, for: .claude, defaults: testDefaults.defaults)
        let credentials = MockCredentialProvider()
        let apiService = MockAPIService()
        let cursor = CountingProviderUsageService(provider: .cursor)
        let viewModel = UsageViewModel(
            credentialProvider: credentials,
            apiService: apiService,
            providerUsageServices: [.cursor: cursor],
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        let outcome = await viewModel.refresh(force: true)

        #expect(outcome == .skipped)
        #expect(await credentials.loadCallCount == 0)
        #expect(await apiService.fetchCallCount == 0)
        #expect(viewModel.snapshot == nil)
        #expect(viewModel.errorMessage == nil, "no missing-credentials error for a provider that is off")
        #expect(viewModel.tokenSnapshot == nil)
        #expect(viewModel.tokenUsageError == nil)
        #expect(viewModel.availableProviders == [.cursor])
    }

    @Test @MainActor func cachedClaudeSnapshotIsIgnoredWhileClaudeIsOff() {
        let testDefaults = TestUserDefaults()
        let usage = Self.makeUsageSnapshot()
        UsageSnapshotStore(defaults: testDefaults.defaults).save(
            snapshot: usage,
            planType: "Pro",
            fetchedAt: usage.fetchedAt
        )
        ProviderSettings.setEnabled(false, for: .claude, defaults: testDefaults.defaults)

        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            defaults: testDefaults.defaults
        )

        #expect(viewModel.snapshot == nil)
        #expect(viewModel.usageSnapshot(for: .claude) == nil)
        #expect(viewModel.availableProviders.isEmpty)
    }

    @Test @MainActor func turningProviderOffHidesItAndStopsSharingIt() async {
        let testDefaults = TestUserDefaults()
        let fetchedAt = Date()
        UsageSnapshotStore(defaults: testDefaults.defaults).save(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [
                Self.providerSnapshot(.codex, fetchedAt: fetchedAt),
                Self.providerSnapshot(.cursor, fetchedAt: fetchedAt),
            ],
            fetchedAt: fetchedAt
        )
        let syncService = MockUsageSyncService()
        let codex = CountingProviderUsageService(provider: .codex)
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            providerUsageServices: [.codex: codex],
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            usageSyncService: syncService,
            defaults: testDefaults.defaults
        )
        #expect(viewModel.availableProviders.contains(.codex))

        await viewModel.setProviderEnabled(.codex, enabled: false)

        #expect(!viewModel.isProviderEnabled(.codex))
        #expect(viewModel.usageSnapshot(for: .codex) == nil)
        #expect(viewModel.availableProviders == [.cursor])
        #expect(await codex.fetchCount == 0)
        let published = await syncService.lastPublishedProviderSnapshots()
        #expect(published?.map(\.provider) == [.cursor])
        let cached = UsageSnapshotStore(defaults: testDefaults.defaults).load()
        #expect(cached?.providerSnapshots.map(\.provider) == [.cursor])
        #expect(ProviderSettings.userDisabledProviders(defaults: testDefaults.defaults) == [.codex])
    }

    @Test @MainActor func turningProviderBackOnFetchesItAgain() async {
        let testDefaults = TestUserDefaults()
        ProviderSettings.setEnabled(false, for: .codex, defaults: testDefaults.defaults)
        let codex = CountingProviderUsageService(provider: .codex)
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            providerUsageServices: [.codex: codex],
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )

        await viewModel.setProviderEnabled(.codex, enabled: true)

        #expect(viewModel.isProviderEnabled(.codex))
        #expect(await codex.fetchCount == 1)
        #expect(viewModel.usageSnapshot(for: .codex) != nil)
    }

    @Test @MainActor func lastEnabledProviderCannotBeTurnedOff() async {
        let testDefaults = TestUserDefaults()
        let viewModel = UsageViewModel(
            credentialProvider: MockCredentialProvider(),
            usageHistoryService: UsageHistoryService(defaults: testDefaults.defaults),
            defaults: testDefaults.defaults
        )
        for provider in [Provider.claude, .codex, .cursor] {
            await viewModel.setProviderEnabled(provider, enabled: false)
        }

        #expect(!viewModel.canDisableProvider(.grok))
        await viewModel.setProviderEnabled(.grok, enabled: false)

        #expect(viewModel.isProviderEnabled(.grok))
        #expect(viewModel.userDisabledProviders == [.claude, .codex, .cursor])
        #expect(viewModel.disabledProviders == [.claude, .codex, .cursor, .openCode, .openCodeGo])
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

    private static func providerSnapshot(_ provider: Provider, fetchedAt: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(
                    utilization: 30,
                    resetsAt: fetchedAt.addingTimeInterval(3_600),
                    windowType: .session
                ),
            ],
            fetchedAt: fetchedAt
        )
    }
}

private actor CountingProviderUsageService: ProviderUsageServiceProtocol {
    let provider: Provider
    private(set) var fetchCount = 0

    init(provider: Provider) {
        self.provider = provider
    }

    func fetchSnapshot() async throws -> ProviderUsageSnapshot? {
        fetchCount += 1
        return ProviderUsageSnapshot(
            provider: provider,
            windows: [
                UsageWindow(
                    utilization: 40,
                    resetsAt: Date().addingTimeInterval(3_600),
                    windowType: .session
                ),
            ],
            fetchedAt: Date()
        )
    }
}
#endif
