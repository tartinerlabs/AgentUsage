//
//  SettingsView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController

    var body: some View {
        TabView {
            GeneralTab()
                .environment(viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            UpdatesTab()
                .environmentObject(updaterController)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 280)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(UsageViewModel.self) private var viewModel
    @StateObject private var launchAtLogin = LaunchAtLoginService.shared

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)

            Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                ForEach(RefreshFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Credentials", value: credentialsStatus)
        }
        .formStyle(.grouped)
    }

    private var credentialsStatus: String {
        if FileManager.default.fileExists(atPath: Constants.credentialsFileURL.path) {
            return "Found"
        } else {
            return "Not found"
        }
    }
}

// MARK: - Updates Tab

private struct UpdatesTab: View {
    @EnvironmentObject private var updaterController: UpdaterController

    var body: some View {
        Form {
            LabeledContent("Check for Updates") {
                Button("Check Now") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
            }

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Version", value: Bundle.main.appVersion)
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            // App Name and Version
            VStack(spacing: 2) {
                Text("ClaudeMeter")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version \(Bundle.main.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("Monitor your Claude API usage directly from the menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // Links
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter/issues")!) {
                    Label("Report Issue", systemImage: "ladybug")
                }
            }
            .buttonStyle(.link)

            Spacer()

            // Copyright
            Text("\u{00A9} 2025 Ru Chern Chong. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif
