//
//  ClaudeMeter_iOSApp.swift
//  ClaudeMeter-iOS
//

import SwiftUI

@main
struct ClaudeMeter_iOSApp: App {
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
