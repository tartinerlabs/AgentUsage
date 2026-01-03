//
//  MainTabView.swift
//  ClaudeMeter-iOS
//

import SwiftUI

/// Main tab container for iOS app
struct MainTabView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .tint(Constants.brandPrimary)
    }
}

#Preview {
    MainTabView()
        .environment(UsageViewModel(
            credentialProvider: iOSCredentialService()
        ))
}
