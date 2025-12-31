//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI

@main
struct ClaudeMeterApp: App {
    @State private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .task {
                    await viewModel.refresh()
                    viewModel.startAutoRefresh()
                }
        } label: {
            Image(systemName: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
