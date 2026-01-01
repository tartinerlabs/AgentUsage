//
//  ClaudeMeter_iOSApp.swift
//  ClaudeMeter-iOS
//

import SwiftUI

@main
struct ClaudeMeter_iOSApp: App {
    @State private var viewModel: UsageViewModel

    init() {
        let credentialService = iOSCredentialService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService
        ))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
                    .environment(viewModel)
            }
        }
    }
}
