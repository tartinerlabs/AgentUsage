//
//  SettingsTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// Settings content for the main window tab
struct SettingsTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("Refresh") {
                Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
            }

            Section("Credentials") {
                LabeledContent("Status", value: credentialsStatus)
            }

            Section("Updates") {
                LabeledContent("Version", value: Bundle.main.appVersion)

                HStack {
                    Text("Check for Updates")
                    Spacer()
                    Button("Check Now") {
                        updaterController.checkForUpdates()
                    }
                    .disabled(!updaterController.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var credentialsStatus: String {
        FileManager.default.fileExists(atPath: Constants.credentialsFileURL.path)
            ? "Found" : "Not found"
    }
}

#Preview {
    SettingsTabView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
        .frame(width: 500, height: 400)
}
#endif
