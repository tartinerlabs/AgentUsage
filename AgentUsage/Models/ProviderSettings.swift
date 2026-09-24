//
//  ProviderSettings.swift
//  AgentUsage
//
//  Which providers the Mac fetches, shows, and shares over Continuity Sync.
//

import Foundation
import AgentUsageKit

/// Provider enablement. `nonisolated` so the token service actor can check it
/// before reading a provider's local logs.
nonisolated enum ProviderSettings {
    /// Providers the app does not ship yet. They are never fetched or shown, and
    /// user-facing copy leaves them out.
    static let unshippedProviders: Set<Provider> = [.openCode, .openCodeGo]

    /// Providers the user can turn on and off, in canonical `Provider` order.
    static var shippedProviders: [Provider] {
        Provider.allCases.filter { !unshippedProviders.contains($0) }
    }

    /// Shipped provider names for user-facing copy, e.g. "Claude, Codex, Cursor, and Grok".
    static var shippedProviderNames: String {
        displayList(shippedProviders)
    }

    /// Joins provider names as an English list: "A", "A and B", "A, B, and C".
    static func displayList(_ providers: [Provider]) -> String {
        let names = providers.map(\.displayName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    /// Providers the user turned off. A stored value that would turn off every
    /// shipped provider is ignored, so at least one provider always stays on.
    static func userDisabledProviders(defaults: UserDefaults) -> Set<Provider> {
        let rawValues = defaults.stringArray(forKey: Constants.disabledProvidersKey) ?? []
        let disabled = Set(rawValues.compactMap(Provider.init(rawValue:)))
            .intersection(shippedProviders)
        return disabled.count < shippedProviders.count ? disabled : []
    }

    /// Whether the app should fetch, show, and share a provider.
    static func isEnabled(_ provider: Provider, defaults: UserDefaults) -> Bool {
        !unshippedProviders.contains(provider)
            && !userDisabledProviders(defaults: defaults).contains(provider)
    }

    /// A thread-safe check for services that run off the main actor. It reads the
    /// stored setting on every call, so changes apply without rebuilding the caller.
    static func enabledCheck(defaults: UserDefaults) -> @Sendable (Provider) -> Bool {
        { provider in isEnabled(provider, defaults: defaults) }
    }

    /// Whether `provider` can be turned off without leaving no provider enabled.
    static func canDisable(_ provider: Provider, userDisabled: Set<Provider>) -> Bool {
        guard shippedProviders.contains(provider), !userDisabled.contains(provider) else {
            return false
        }
        return shippedProviders.contains { $0 != provider && !userDisabled.contains($0) }
    }

    /// Turn a provider on or off and persist the result. Turning off the last
    /// enabled provider, or changing an unshipped one, is refused.
    /// - Returns: The user-disabled set now in effect.
    @discardableResult
    static func setEnabled(
        _ enabled: Bool,
        for provider: Provider,
        defaults: UserDefaults
    ) -> Set<Provider> {
        var disabled = userDisabledProviders(defaults: defaults)
        guard shippedProviders.contains(provider) else { return disabled }
        if enabled {
            disabled.remove(provider)
        } else {
            guard canDisable(provider, userDisabled: disabled) else { return disabled }
            disabled.insert(provider)
        }
        defaults.set(
            shippedProviders.filter(disabled.contains).map(\.rawValue),
            forKey: Constants.disabledProvidersKey
        )
        return disabled
    }
}
