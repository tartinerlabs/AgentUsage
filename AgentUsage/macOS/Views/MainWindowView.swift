//
//  MainWindowView.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI

/// Tab identifiers for the main window
enum MainWindowTab: String, CaseIterable, Identifiable {
    case dashboard
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "gauge.with.dots.needle.bottom.50percent"
        case .settings:
            return "slider.horizontal.3"
        case .about:
            return "info.circle"
        }
    }
}

/// Main macOS app window containing the Dashboard, Settings, and About surfaces.
struct MainWindowView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard

    var body: some View {
        NavigationSplitView {
            List(MainWindowTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("AgentUsage")
        } detail: {
            selectedContent
                .environment(viewModel)
                .environmentObject(updaterController)
                .navigationTitle(selectedTab.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 920, minHeight: 560, idealHeight: 680)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardTabView()
        case .settings:
            SettingsTabView()
        case .about:
            AboutTabView()
        }
    }
}

#Preview {
    MainWindowView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif
