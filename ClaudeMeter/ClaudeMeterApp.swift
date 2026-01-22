//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI
import SwiftData

@main
struct ClaudeMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: UsageViewModel
    @StateObject private var updaterController = UpdaterController()
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard
    @Environment(\.openWindow) private var openWindow

    let modelContainer: ModelContainer

    init() {
        // Initialize SwiftData container
        let schema = Schema([TokenLogEntry.self, ImportedFile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }

        let credentialService = MacOSCredentialService()
        let tokenService = TokenUsageService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService,
            tokenService: tokenService,
            modelContext: modelContainer.mainContext
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
            // Note: initializeIfNeeded() is called from Window's .task - no duplicate needed here
        }
        .menuBarExtraStyle(.window)
    }
}
