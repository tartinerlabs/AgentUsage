//
//  StatusItemMenuTests.swift
//  AgentUsageTests
//

#if os(macOS)
import AppKit
import Testing
@testable import AgentUsage

@Suite("Status Item Menu")
@MainActor
struct StatusItemMenuTests {
    @Test("Right-click menu lists Refresh, Open Dashboard, Settings, then Quit")
    func menuItemsInOrder() {
        let menu = AppDelegate.makeStatusItemMenu(target: nil)

        #expect(menu.items.map(\.title) == [
            "Refresh",
            "Open Dashboard",
            "Settings…",
            "",
            "Quit \(Constants.appDisplayName)",
        ])
        #expect(menu.items[3].isSeparatorItem)
    }

    @Test("Items dispatch to the delegate's actions and Quit terminates")
    func menuItemActions() {
        let delegate = AppDelegate()
        let menu = AppDelegate.makeStatusItemMenu(target: delegate)

        #expect(menu.items[0].action == #selector(AppDelegate.refreshFromStatusItemMenu(_:)))
        #expect(menu.items[1].action == #selector(AppDelegate.openDashboardFromStatusItemMenu(_:)))
        #expect(menu.items[2].action == #selector(AppDelegate.openSettingsFromStatusItemMenu(_:)))
        #expect(menu.items[4].action == #selector(NSApplication.terminate(_:)))
        for item in menu.items[0...2] {
            #expect(item.target === delegate)
        }
    }

    @Test("Settings uses the app's Command-comma shortcut")
    func settingsKeyEquivalent() {
        let settings = AppDelegate.makeStatusItemMenu(target: nil).items[2]

        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == .command)
    }
}
#endif
