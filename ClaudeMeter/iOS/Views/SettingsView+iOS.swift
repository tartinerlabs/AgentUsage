//
//  SettingsView+iOS.swift
//  ClaudeMeter
//

#if os(iOS)
import SwiftUI

/// iOS Settings view
struct SettingsView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
            } header: {
                Text("Auto Refresh")
            } footer: {
                Text("How often to automatically fetch usage data.")
            }

            Section("Sync Status") {
                LabeledContent("Credentials") {
                    if viewModel.errorMessage == nil && viewModel.snapshot != nil {
                        Label("Synced", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if viewModel.errorMessage != nil {
                        Label("Not synced", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Label("Checking...", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)

                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter")!) {
                    HStack {
                        Label("GitHub", systemImage: "link")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter/issues")!) {
                    HStack {
                        Label("Report Issue", systemImage: "ladybug")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(UsageViewModel(
                credentialProvider: iOSCredentialService()
            ))
    }
}
#endif
