//
//  MenuBarSettingsManager.swift
//  AgentUsage
//
//  Manages menu bar display settings (macOS only)
//

#if os(macOS)
import AgentUsageKit
import Foundation

/// A quota window the user can pin to the compact menu-bar strip.
struct MenuBarWindowOption: Identifiable, Hashable {
    let id: UsageWindowID
    let displayName: String
}

/// Manages the ordered quota windows pinned to the compact menu-bar strip.
@MainActor @Observable
final class MenuBarSettingsManager {
    static let maximumPinsPerProvider = 2
    /// Every provider that reports live quota windows may appear in the strip.
    static let supportedProviders: [Provider] = Provider.allCases.filter { $0.supports(.rateWindows) }
    /// Default and allowed values for `maximumProviders`.
    static let defaultMaximumProviders = 3
    static let maximumProvidersRange = 1...supportedProviders.count

    /// Upper bound on providers rendered in the strip, most recently used first.
    var maximumProviders: Int {
        get { storedMaximumProviders }
        set {
            storedMaximumProviders = Self.clampedMaximumProviders(newValue)
            defaults.set(storedMaximumProviders, forKey: Key.maximumProviders)
        }
    }

    private var storedMaximumProviders: Int

    private static func clampedMaximumProviders(_ value: Int) -> Int {
        min(max(value, maximumProvidersRange.lowerBound), maximumProvidersRange.upperBound)
    }

    private enum Key {
        static let schemaVersion = "menuBarPinnedWindowsSchemaVersion"
        static let pinsPrefix = "menuBarPinnedWindows."
        static let maximumProviders = "menuBarMaximumProviders"

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
    private var pinnedWindowsByProvider: [Provider: [UsageWindowID]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.storedMaximumProviders = Self.clampedMaximumProviders(
            defaults.object(forKey: Key.maximumProviders) as? Int ?? Self.defaultMaximumProviders
        )

        if defaults.integer(forKey: Key.schemaVersion) >= Self.currentSchemaVersion {
            self.pinnedWindowsByProvider = Self.loadCurrentPins(from: defaults)
        } else {
            self.pinnedWindowsByProvider = Self.migrateLegacyPins(from: defaults)
            persistAllPins()
            defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
        }
    }

    /// Pins applied the first time a provider is seen, before the user customises it.
    static func defaultPins(for provider: Provider) -> [UsageWindowID] {
        switch provider {
        case .claude: [.session, .opus].map(id)
        case .codex: [.codexFiveHour, .codexWeekly].map(id)
        case .openCode, .openCodeGo: [.openCodeGoFiveHour, .openCodeGoWeekly].map(id)
        case .cursor: ["cursor.total"]
        case .grok: ["grok.monthly"]
        }
    }

    /// Pinnable windows: whatever the live snapshot reports, plus any pinned window that
    /// is not currently live so the user can still unpin it.
    static func windowOptions(
        snapshot: ProviderUsageSnapshot?,
        pinned: [UsageWindowID]
    ) -> [MenuBarWindowOption] {
        var options = (snapshot?.windows ?? []).map {
            MenuBarWindowOption(id: $0.windowID, displayName: $0.displayName)
        }
        for id in pinned where !options.contains(where: { $0.id == id }) {
            options.append(MenuBarWindowOption(
                id: id,
                displayName: UsageWindowType(rawValue: id.rawValue)?.displayName ?? id.rawValue
            ))
        }
        return options
    }

    func pinnedWindows(for provider: Provider) -> [UsageWindowID] {
        pinnedWindowsByProvider[provider] ?? []
    }

    func isPinned(_ window: UsageWindowID, for provider: Provider) -> Bool {
        pinnedWindows(for: provider).contains(window)
    }

    func canPin(_ window: UsageWindowID, for provider: Provider) -> Bool {
        isPinned(window, for: provider)
            || pinnedWindows(for: provider).count < Self.maximumPinsPerProvider
    }

    func setPinned(_ window: UsageWindowID, for provider: Provider, isPinned: Bool) {
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

    private static func id(_ type: UsageWindowType) -> UsageWindowID {
        UsageWindowID(rawValue: type.rawValue)
    }

    private static func loadCurrentPins(from defaults: UserDefaults) -> [Provider: [UsageWindowID]] {
        Dictionary(uniqueKeysWithValues: supportedProviders.map { provider in
            guard let rawValues = defaults.stringArray(forKey: storageKey(for: provider)) else {
                return (provider, defaultPins(for: provider))
            }
            return (provider, sanitized(rawValues: rawValues))
        })
    }

    private static func migrateLegacyPins(from defaults: UserDefaults) -> [Provider: [UsageWindowID]] {
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

        var pins = Dictionary(uniqueKeysWithValues: supportedProviders.map {
            ($0, defaultPins(for: $0))
        })

        if hasLegacyClaudeSettings {
            let selected = claudeLegacyKeys.compactMap { key, window in
                defaults.bool(forKey: key) ? window : nil
            }
            // The old renderer always restored Session when every toggle was off.
            let claudePins = selected.isEmpty
                ? [.session]
                : Array(selected.prefix(maximumPinsPerProvider))
            pins[.claude] = claudePins.map(id)
        }

        if defaults.object(forKey: Key.codex) != nil, !defaults.bool(forKey: Key.codex) {
            pins[.codex] = []
        }

        return pins
    }

    private static func sanitized(rawValues: [String]) -> [UsageWindowID] {
        var result: [UsageWindowID] = []
        for rawValue in rawValues {
            let window = UsageWindowID(rawValue: rawValue)
            guard !result.contains(window), result.count < maximumPinsPerProvider else { continue }
            result.append(window)
        }
        return result
    }

    private static func storageKey(for provider: Provider) -> String {
        Key.pinsPrefix + provider.rawValue
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
