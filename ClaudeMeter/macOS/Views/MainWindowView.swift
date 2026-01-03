//
//  MainWindowView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// Tab identifiers for the main window
enum MainWindowTab: String, CaseIterable {
    case dashboard
    case settings
    case about
}

/// Main window containing TabView with Dashboard, Settings, and About tabs
struct MainWindowView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardTabView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }
                .tag(MainWindowTab.dashboard)

            SettingsTabView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(MainWindowTab.settings)

            AboutTabView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(MainWindowTab.about)
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 450)
    }
}

#Preview {
    MainWindowView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif
