//
//  MenuBarSettingsManager.swift
//  ClaudeMeter
//
//  Manages menu bar display settings (macOS only)
//

#if os(macOS)
import Foundation

/// Manages menu bar display settings
@MainActor @Observable
final class MenuBarSettingsManager {
    private enum Key {
        static let session = "menuBarShowSession"
        static let allModels = "menuBarShowAllModels"
        static let sonnet = "menuBarShowSonnet"
        static let design = "menuBarShowDesign"
        static let fable = "menuBarShowFable"
        static let codex = "menuBarShowCodex"
        static let extraUsage = "menuBarShowExtraUsage"
    }

    private let defaults: UserDefaults

    /// Show session (5h) usage in menu bar
    var menuBarShowSession: Bool {
        didSet {
            defaults.set(menuBarShowSession, forKey: Key.session)
        }
    }

    /// Show all models (7d) usage in menu bar
    var menuBarShowAllModels: Bool {
        didSet {
            defaults.set(menuBarShowAllModels, forKey: Key.allModels)
        }
    }

    /// Show Sonnet (7d) usage in menu bar
    var menuBarShowSonnet: Bool {
        didSet {
            defaults.set(menuBarShowSonnet, forKey: Key.sonnet)
        }
    }

    /// Show Claude Design (7d) usage in menu bar
    var menuBarShowDesign: Bool {
        didSet {
            defaults.set(menuBarShowDesign, forKey: Key.design)
        }
    }

    /// Show Fable (7d) usage in menu bar
    var menuBarShowFable: Bool {
        didSet {
            defaults.set(menuBarShowFable, forKey: Key.fable)
        }
    }

    /// Show Codex (5h) usage in menu bar
    var menuBarShowCodex: Bool {
        didSet {
            defaults.set(menuBarShowCodex, forKey: Key.codex)
        }
    }

    /// Show Claude extra-usage cost in menu bar
    var menuBarShowExtraUsage: Bool {
        didSet {
            defaults.set(menuBarShowExtraUsage, forKey: Key.extraUsage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.menuBarShowSession = defaults.object(forKey: Key.session) as? Bool ?? true
        self.menuBarShowAllModels = defaults.object(forKey: Key.allModels) as? Bool ?? false
        self.menuBarShowSonnet = defaults.object(forKey: Key.sonnet) as? Bool ?? false
        self.menuBarShowDesign = defaults.object(forKey: Key.design) as? Bool ?? false
        self.menuBarShowFable = defaults.object(forKey: Key.fable) as? Bool ?? false
        self.menuBarShowCodex = defaults.object(forKey: Key.codex) as? Bool ?? false
        self.menuBarShowExtraUsage = defaults.object(forKey: Key.extraUsage) as? Bool ?? true
    }
}
#endif
