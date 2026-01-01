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
        @Bindable var viewModel = viewModel

        Form {
            Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                ForEach(RefreshFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }

            LabeledContent("Check for Updates") {
                Button("Check Now") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
            }

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Version", value: Bundle.main.appVersion)
            LabeledContent("Credentials", value: credentialsStatus)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 200)
    }

    private var credentialsStatus: String {
        if FileManager.default.fileExists(atPath: Constants.credentialsFileURL.path) {
            return "Found"
        } else {
            return "Not found"
        }
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
