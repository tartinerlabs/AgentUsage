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

    init() {
        let defaults = UserDefaults.standard
        self.menuBarShowSession = defaults.object(forKey: "menuBarShowSession") as? Bool ?? true
        self.menuBarShowAllModels = defaults.object(forKey: "menuBarShowAllModels") as? Bool ?? false
        self.menuBarShowSonnet = defaults.object(forKey: "menuBarShowSonnet") as? Bool ?? false
    }
}

/// Menu bar display window options
enum MenuBarDisplayWindow: String, CaseIterable, Identifiable {
    case session = "session"
    case allModels = "allModels"
    case sonnet = "sonnet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return "Session (5h)"
        case .allModels: return "All Models (7d)"
        case .sonnet: return "Sonnet (7d)"
        }
    }
}
#endif
