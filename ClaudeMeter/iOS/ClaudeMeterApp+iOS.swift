//
//  ClaudeMeterApp+iOS.swift
//  ClaudeMeter
//

#if os(iOS)
import SwiftUI

@main
struct ClaudeMeterApp_iOS: App {
    @State private var viewModel: UsageViewModel

    init() {
        let credentialService = iOSCredentialService()
        _viewModel = State(initialValue: UsageViewModel(
            credentialProvider: credentialService,
            tokenService: nil  // Token usage not available on iOS (MVP)
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
#endif
