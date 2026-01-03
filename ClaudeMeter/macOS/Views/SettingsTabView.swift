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

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Refresh Section
                settingsCard(title: "Refresh") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Refresh Interval")
                                .font(.body)
                            Text("How often to fetch usage data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $viewModel.refreshInterval) {
                            ForEach(RefreshFrequency.allCases) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                // Notifications Section
                settingsCard(title: "Notifications") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Usage Alerts")
                                    .font(.body)
                                Text("Notify when usage crosses 25%, 50%, 75%, or 100%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.notificationsEnabled)
                                .labelsHidden()
                        }

                        if viewModel.notificationsEnabled {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Test Notification")
                                        .font(.body)
                                    Text("Send a test notification to verify setup")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Test") {
                                    Task { await NotificationService.shared.sendTestNotification() }
                                }
                            }
                        }
                    }
                }

                // Credentials Section
                settingsCard(title: "Credentials") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Status")
                                    .font(.body)
                                Text("Claude CLI credentials file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: credentialsFound ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(credentialsFound ? Color.green : Color.red)
                                Text(credentialsFound ? "Found" : "Not found")
                                    .foregroundStyle(credentialsFound ? Color.primary : Color.red)
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Location")
                                    .font(.body)
                                Text(Constants.credentialsFileURL.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                NSWorkspace.shared.selectFile(
                                    Constants.credentialsFileURL.path,
                                    inFileViewerRootedAtPath: Constants.credentialsFileURL.deletingLastPathComponent().path
                                )
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!credentialsFound)
                        }
                    }
                }

                // Updates Section
                settingsCard(title: "Updates") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Version")
                                    .font(.body)
                                Text("Installed app version")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Bundle.main.appVersion)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Check for Updates")
                                    .font(.body)
                                Text("Download and install the latest version")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check Now") {
                                updaterController.checkForUpdates()
                            }
                            .disabled(!updaterController.canCheckForUpdates)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var credentialsFound: Bool {
        FileManager.default.fileExists(atPath: Constants.credentialsFileURL.path)
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
}

#Preview {
    SettingsTabView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
        .frame(width: 500, height: 400)
}
#endif
