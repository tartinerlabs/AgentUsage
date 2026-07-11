//
//  MenuBarSettingsManager.swift
//  AgentUsage
//
//  Manages menu bar display settings (macOS only)
//

#if os(macOS)
import AgentUsageKit
import Foundation

/// Manages the ordered quota windows pinned to the compact menu-bar strip.
@MainActor @Observable
final class MenuBarSettingsManager {
    static let maximumPinsPerProvider = 2
    static let supportedProviders: [Provider] = [.claude, .codex]

    private enum Key {
        static let schemaVersion = "menuBarPinnedWindowsSchemaVersion"
        static let claudePins = "menuBarPinnedWindows.claude"
        static let codexPins = "menuBarPinnedWindows.codex"

        // Legacy keys are read once for migration and intentionally retained for rollback.
        static let session = "menuBarShowSession"
        static let allModels = "menuBarShowAllModels"
        static let sonnet = "menuBarShowSonnet"
        static let design = "menuBarShowDesign"
        static let fable = "menuBarShowFable"
        static let codex = "menuBarShowCodex"
    }

    private static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private var pinnedWindowsByProvider: [Provider: [UsageWindowType]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.integer(forKey: Key.schemaVersion) >= Self.currentSchemaVersion {
            self.pinnedWindowsByProvider = Self.loadCurrentPins(from: defaults)
        } else {
            self.pinnedWindowsByProvider = Self.migrateLegacyPins(from: defaults)
            persistAllPins()
            defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
        }
    }

    static func supportedWindows(for provider: Provider) -> [UsageWindowType] {
        switch provider {
        case .claude: [.session, .opus, .sonnet, .design, .fable]
        case .codex: [.codexFiveHour, .codexWeekly]
        case .openCode: []
        }
    }

    func pinnedWindows(for provider: Provider) -> [UsageWindowType] {
        pinnedWindowsByProvider[provider] ?? []
    }

    func isPinned(_ window: UsageWindowType, for provider: Provider) -> Bool {
        pinnedWindows(for: provider).contains(window)
    }

    func canPin(_ window: UsageWindowType, for provider: Provider) -> Bool {
        isPinned(window, for: provider)
            || pinnedWindows(for: provider).count < Self.maximumPinsPerProvider
    }

    func setPinned(_ window: UsageWindowType, for provider: Provider, isPinned: Bool) {
        guard Self.supportedWindows(for: provider).contains(window) else { return }

        var pins = pinnedWindows(for: provider)
        if isPinned {
            guard !pins.contains(window), pins.count < Self.maximumPinsPerProvider else { return }
            pins.append(window)
        } else {
            pins.removeAll { $0 == window }
        }

        pinnedWindowsByProvider[provider] = pins
        defaults.set(pins.map(\.rawValue), forKey: Self.storageKey(for: provider))
    }

    private static func loadCurrentPins(from defaults: UserDefaults) -> [Provider: [UsageWindowType]] {
        Dictionary(uniqueKeysWithValues: supportedProviders.map { provider in
            let rawValues = defaults.stringArray(forKey: storageKey(for: provider)) ?? []
            return (provider, sanitized(rawValues: rawValues, for: provider))
        })
    }

    private static func migrateLegacyPins(from defaults: UserDefaults) -> [Provider: [UsageWindowType]] {
        let claudeLegacyKeys: [(String, UsageWindowType)] = [
            (Key.session, .session),
            (Key.allModels, .opus),
            (Key.sonnet, .sonnet),
            (Key.design, .design),
            (Key.fable, .fable),
        ]
        let hasLegacyClaudeSettings = claudeLegacyKeys.contains {
            defaults.object(forKey: $0.0) != nil
        }

        let claudePins: [UsageWindowType]
        if hasLegacyClaudeSettings {
            let selected = claudeLegacyKeys.compactMap { key, window in
                defaults.bool(forKey: key) ? window : nil
            }
            // The old renderer always restored Session when every toggle was off.
            claudePins = selected.isEmpty
                ? [.session]
                : Array(selected.prefix(maximumPinsPerProvider))
        } else {
            claudePins = [.session, .opus]
        }

        let codexPins: [UsageWindowType]
        if defaults.object(forKey: Key.codex) != nil {
            codexPins = defaults.bool(forKey: Key.codex)
                ? [.codexFiveHour, .codexWeekly]
                : []
        } else {
            codexPins = [.codexFiveHour, .codexWeekly]
        }

        return [.claude: claudePins, .codex: codexPins]
    }

    private static func sanitized(rawValues: [String], for provider: Provider) -> [UsageWindowType] {
        let supported = supportedWindows(for: provider)
        var result: [UsageWindowType] = []

        for rawValue in rawValues {
            guard let window = UsageWindowType(rawValue: rawValue),
                  supported.contains(window),
                  !result.contains(window),
                  result.count < maximumPinsPerProvider else { continue }
            result.append(window)
        }
        return result
    }

    private static func storageKey(for provider: Provider) -> String {
        switch provider {
        case .claude: Key.claudePins
        case .codex: Key.codexPins
        case .openCode: "menuBarPinnedWindows.unsupported"
        }
    }

    private func persistAllPins() {
        for provider in Self.supportedProviders {
            defaults.set(
                pinnedWindows(for: provider).map(\.rawValue),
                forKey: Self.storageKey(for: provider)
            )
        }
    }
}
#endif
