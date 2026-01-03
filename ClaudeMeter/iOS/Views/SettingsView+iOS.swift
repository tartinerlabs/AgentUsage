//
//  SettingsView+iOS.swift
//  ClaudeMeter
//

#if os(iOS)
import SwiftUI

/// iOS Settings view
struct SettingsView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var credentialJSON = ""
    @State private var saveStatus: SaveStatus?
    @State private var showingClearConfirmation = false

    private enum SaveStatus {
        case success
        case error(String)
    }

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

            Section("Credential Status") {
                LabeledContent("Status") {
                    if viewModel.errorMessage == nil && viewModel.snapshot != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if viewModel.errorMessage != nil {
                        Label("Not connected", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Label("Checking...", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                TextEditor(text: $credentialJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    saveCredentials()
                } label: {
                    HStack {
                        Label("Save Credentials", systemImage: "key.fill")
                        Spacer()
                        if case .success = saveStatus {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(credentialJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if case .error(let message) = saveStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear Credentials", systemImage: "trash")
                }
            } header: {
                Text("Manual Entry")
            } footer: {
                Text("Paste the contents of ~/.claude/.credentials.json from your Mac. This is a workaround until iCloud Keychain sync is available.")
            }

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear Credentials?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                clearCredentials()
            }
        } message: {
            Text("This will remove your saved credentials. You'll need to enter them again.")
        }
    }

    private func saveCredentials() {
        let service = iOSCredentialService()
        Task {
            do {
                try await service.saveCredentialsFromJSON(credentialJSON)
                await MainActor.run {
                    saveStatus = .success
                    credentialJSON = ""
                }
                // Refresh to load new credentials
                await viewModel.refresh(force: true)
            } catch {
                await MainActor.run {
                    saveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func clearCredentials() {
        let service = iOSCredentialService()
        Task {
            await service.clearCredentials()
            await MainActor.run {
                credentialJSON = ""
                saveStatus = nil
            }
            await viewModel.refresh(force: true)
        }
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
