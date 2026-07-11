//
//  AgentUsage_iOSApp.swift
//  AgentUsage-iOS
//

import SwiftUI

@main
struct AgentUsage_iOSApp: App {
    @State private var viewModel: UsageViewModel

    init() {
        // Use DependencyContainer for view model creation
        _viewModel = State(initialValue: DependencyContainer.createUsageViewModel())
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(viewModel)
        }
    }
}
