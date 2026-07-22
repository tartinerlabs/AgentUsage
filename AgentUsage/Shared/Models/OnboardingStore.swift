//
//  OnboardingStore.swift
//  AgentUsage
//

import Foundation
import Observation

enum OnboardingPlatform: String, Sendable {
    case mac
    case mobile

    static var current: Self {
        #if os(macOS)
        .mac
        #else
        .mobile
        #endif
    }
}

enum OnboardingStatus: String, Equatable, Sendable {
    case pending
    case completed
    case skipped
}

/// Persists first-run progress independently on Mac and mobile devices.
/// Presentation remains local so completing setup on one device never hides the
/// relevant explanation on another.
@MainActor @Observable
final class OnboardingStore {
    static let currentVersion = 1

    private(set) var isPresented = false
    private(set) var status: OnboardingStatus

    private let platform: OnboardingPlatform
    private let defaults: UserDefaults

    init(
        platform: OnboardingPlatform = .current,
        defaults: UserDefaults = .standard
    ) {
        self.platform = platform
        self.defaults = defaults

        Self.migrateLegacyStateIfNeeded(platform: platform, defaults: defaults)
        status = Self.persistedStatus(platform: platform, defaults: defaults)
    }

    var shouldPresent: Bool {
        status == .pending
    }

    func presentIfNeeded() {
        guard shouldPresent else { return }
        isPresented = true
    }

    func present() {
        isPresented = true
    }

    func complete() {
        persist(.completed)
    }

    func skip() {
        persist(.skipped)
    }

    func dismissWithoutCompleting() {
        isPresented = false
    }

    private func persist(_ newStatus: OnboardingStatus) {
        defaults.set(newStatus.rawValue, forKey: statusKey)
        defaults.set(Self.currentVersion, forKey: versionKey)
        status = newStatus
        isPresented = false
    }

    private var statusKey: String {
        "onboarding.\(platform.rawValue).status"
    }

    private var versionKey: String {
        "onboarding.\(platform.rawValue).version"
    }

    private static func persistedStatus(
        platform: OnboardingPlatform,
        defaults: UserDefaults
    ) -> OnboardingStatus {
        let version = defaults.integer(forKey: "onboarding.\(platform.rawValue).version")
        guard version >= currentVersion,
              let rawValue = defaults.string(forKey: "onboarding.\(platform.rawValue).status"),
              let status = OnboardingStatus(rawValue: rawValue) else {
            return .pending
        }
        return status
    }

    private static func migrateLegacyStateIfNeeded(
        platform: OnboardingPlatform,
        defaults: UserDefaults
    ) {
        let versionKey = "onboarding.\(platform.rawValue).version"
        guard defaults.object(forKey: versionKey) == nil else { return }

        let hasLegacyCompletion: Bool
        switch platform {
        case .mac:
            hasLegacyCompletion = defaults.bool(forKey: "hasCompletedDataAccessOnboarding")
        case .mobile:
            hasLegacyCompletion = defaults.object(forKey: UsageSnapshotStore.snapshotKey) != nil
                || defaults.object(forKey: UsageSnapshotStore.providerSnapshotsKey) != nil
                || defaults.object(forKey: UsageSnapshotStore.fetchTimeKey) != nil
        }

        guard hasLegacyCompletion else { return }
        defaults.set(OnboardingStatus.completed.rawValue, forKey: "onboarding.\(platform.rawValue).status")
        defaults.set(currentVersion, forKey: versionKey)
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let localDataAccessGranted = Notification.Name("localDataAccessGranted")
}
