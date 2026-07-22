//
//  OnboardingStoreTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
@testable import AgentUsage

@Suite("Onboarding Store", .serialized)
@MainActor
struct OnboardingStoreTests {
    @Test("A new install presents onboarding")
    func newInstallPresentsOnboarding() {
        let storage = TestUserDefaults()
        let store = OnboardingStore(platform: .mac, defaults: storage.defaults)

        #expect(store.status == .pending)
        #expect(store.shouldPresent)

        store.presentIfNeeded()
        #expect(store.isPresented)
    }

    @Test("Completion persists independently by platform")
    func completionPersistsByPlatform() {
        let storage = TestUserDefaults()
        let macStore = OnboardingStore(platform: .mac, defaults: storage.defaults)

        macStore.present()
        macStore.complete()

        let restoredMacStore = OnboardingStore(platform: .mac, defaults: storage.defaults)
        let mobileStore = OnboardingStore(platform: .mobile, defaults: storage.defaults)
        #expect(restoredMacStore.status == .completed)
        #expect(!restoredMacStore.shouldPresent)
        #expect(mobileStore.status == .pending)
    }

    @Test("Skipping is distinct from completion and can be replayed")
    func skipAndReplay() {
        let storage = TestUserDefaults()
        let store = OnboardingStore(platform: .mobile, defaults: storage.defaults)

        store.skip()
        #expect(store.status == .skipped)
        #expect(!store.shouldPresent)

        store.present()
        #expect(store.isPresented)
        #expect(store.status == .skipped)
    }

    @Test("Closing without a decision leaves setup pending")
    func dismissalDoesNotCompleteSetup() {
        let storage = TestUserDefaults()
        let store = OnboardingStore(platform: .mac, defaults: storage.defaults)

        store.present()
        store.dismissWithoutCompleting()

        #expect(!store.isPresented)
        #expect(store.status == .pending)
        #expect(store.shouldPresent)
    }

    @Test("Legacy Mac completion migrates without replaying onboarding")
    func migratesLegacyMacCompletion() {
        let storage = TestUserDefaults()
        storage.defaults.set(true, forKey: "hasCompletedDataAccessOnboarding")

        let store = OnboardingStore(platform: .mac, defaults: storage.defaults)

        #expect(store.status == .completed)
        #expect(!store.shouldPresent)
    }

    @Test("Existing mobile snapshots migrate without replaying onboarding")
    func migratesExistingMobileSnapshot() {
        let storage = TestUserDefaults()
        storage.defaults.set(Date().timeIntervalSince1970, forKey: UsageSnapshotStore.fetchTimeKey)

        let store = OnboardingStore(platform: .mobile, defaults: storage.defaults)

        #expect(store.status == .completed)
        #expect(!store.shouldPresent)
    }
}
