//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var viewModel: UsageViewModel
    @StateObject private var updaterController = UpdaterController()

    init() {
        let credentialService = MacOSCredentialService()
        let tokenService = TokenUsageService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService,
            tokenService: tokenService
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .task {
                    await viewModel.initializeIfNeeded()
                }
        } label: {
            MenuBarIconView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(viewModel)
                .environmentObject(updaterController)
        }

        Window("About ClaudeMeter", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
