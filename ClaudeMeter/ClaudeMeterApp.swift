//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI

@main
struct ClaudeMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: UsageViewModel
    @StateObject private var updaterController = UpdaterController()
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard
    @Environment(\.openWindow) private var openWindow

    init() {
        let credentialService = MacOSCredentialService()
        let tokenService = TokenUsageService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService,
            tokenService: tokenService
        ))
    }

    var body: some Scene {
        // Main window (opened from menu bar)
        Window("ClaudeMeter", id: Constants.mainWindowID) {
            MainWindowView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .task {
                    await viewModel.initializeIfNeeded()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    selectedTab = .settings
                    openWindow(id: Constants.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Menu bar popover
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environmentObject(updaterController)
        } label: {
            MenuBarIconView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .task {
                    await viewModel.initializeIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
