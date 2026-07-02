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
    /// Show session (5h) usage in menu bar
    var menuBarShowSession: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowSession, forKey: "menuBarShowSession")
        }
    }

    /// Show all models (7d) usage in menu bar
    var menuBarShowAllModels: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowAllModels, forKey: "menuBarShowAllModels")
        }
    }

    /// Show Sonnet (7d) usage in menu bar
    var menuBarShowSonnet: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowSonnet, forKey: "menuBarShowSonnet")
        }
    }

    /// Show Claude Design (7d) usage in menu bar
    var menuBarShowDesign: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowDesign, forKey: "menuBarShowDesign")
        }
    }

    /// Show Fable (7d) usage in menu bar
    var menuBarShowFable: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowFable, forKey: "menuBarShowFable")
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.menuBarShowSession = defaults.object(forKey: "menuBarShowSession") as? Bool ?? true
        self.menuBarShowAllModels = defaults.object(forKey: "menuBarShowAllModels") as? Bool ?? false
        self.menuBarShowSonnet = defaults.object(forKey: "menuBarShowSonnet") as? Bool ?? false
        self.menuBarShowDesign = defaults.object(forKey: "menuBarShowDesign") as? Bool ?? false
        self.menuBarShowFable = defaults.object(forKey: "menuBarShowFable") as? Bool ?? false
    }
}

/// Menu bar display window options
enum MenuBarDisplayWindow: String, CaseIterable, Identifiable {
    case session = "session"
    case allModels = "allModels"
    case sonnet = "sonnet"
    case design = "design"
    case fable = "fable"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return "Session (5h)"
        case .allModels: return "All Models (7d)"
        case .sonnet: return "Sonnet (7d)"
        case .design: return "Claude Design (7d)"
        case .fable: return "Fable (7d)"
        }
    }
}
#endif
