//
//  MainTabView.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI

/// Main tab container for iOS app
struct MainTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var onboardingStore = OnboardingStore(platform: .mobile)

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar")
            }

            NavigationStack {
                ClaudeWrappedView()
            }
            .tabItem {
                Label("Wrapped", systemImage: "gift")
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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
                onboardingStore.present()
            } else {
                onboardingStore.presentIfNeeded()
            }
            #else
            onboardingStore.presentIfNeeded()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            onboardingStore.present()
        }
        .fullScreenCover(isPresented: onboardingPresentation) {
            ContinuityOnboardingView(
                onComplete: { onboardingStore.complete() },
                onSkip: { onboardingStore.skip() }
            )
            .environment(viewModel)
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { onboardingStore.isPresented },
            set: { isPresented in
                if !isPresented {
                    onboardingStore.dismissWithoutCompleting()
                }
            }
        )
    }
}

#Preview {
    MainTabView()
        .environment(UsageViewModel(
            credentialProvider: iOSCredentialService()
        ))
}
#endif
