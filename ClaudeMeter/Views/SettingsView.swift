//
//  SettingsView.swift
//  ClaudeMeter
//

import SwiftUI

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
                Text("General")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Credentials", value: credentialsStatus)
            } header: {
                Text("About")
            }
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
        .environment(UsageViewModel())
}
