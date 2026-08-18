//
//  SettingsTabView.swift
//  AgentUsage
//

#if os(macOS)
import AgentUsageKit
import AppKit
import SwiftUI

/// Settings content for the main window tab
struct SettingsTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    // Direct-distribution updater support is dormant while releases use App Store/TestFlight.
    // @EnvironmentObject private var updaterController: UpdaterController

    private let contentWidth: CGFloat = 760

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader

                ContinuitySettingsCard()

                GeneralSettingsCard()

                LocalDataAccessCard()

                NotificationSettingsCard()

                BlogUsageSyncCard()

                #if DEBUG
                // Debug Section (only in debug builds)
                settingsCard(title: "Debug", systemImage: "ladybug") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Simulate 100% Usage")
                                    .font(.body)
                                Text("Show countdown in menu bar as if at limit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.debugSimulate100Percent)
                                .labelsHidden()
                        }

                        if viewModel.debugSimulate100Percent {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Test Reset Notification")
                                        .font(.body)
                                    Text("Simulate a usage window reset")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Send") {
                                    Task { await NotificationService.shared.sendTestResetNotification() }
                                }
                            }
                        }

                        // Restore with the updater integration for a future direct-distribution build.
                        /*
                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Force Background Check")
                                    .font(.body)
                                Text("Trigger a silent update check")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check") {
                                updaterController.checkForUpdatesInBackground()
                            }
                        }
                        */
                    }
                }
                #endif

                // App Store and TestFlight own update discovery and installation. Restore this
                // card only if a separate direct-distribution build brings Sparkle back.
                /*
                if !Bundle.main.isAppStoreBuild {
                    settingsCard(title: "Updates", systemImage: "arrow.down.circle") {
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
                                    Text("Automatic Updates")
                                        .font(.body)
                                    Text("Check for updates automatically")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { updaterController.automaticallyChecksForUpdates },
                                    set: { updaterController.automaticallyChecksForUpdates = $0 }
                                ))
                                .labelsHidden()
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

                                if let result = updaterController.lastCheckResult {
                                    HStack(spacing: 4) {
                                        Image(systemName: result.systemImage)
                                            .foregroundStyle(resultColor(for: result))
                                        Text(result.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                if updaterController.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Check Now") {
                                        updaterController.checkForUpdates()
                                    }
                                    .disabled(!updaterController.canCheckForUpdates)
                                }
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Checked")
                                        .font(.body)
                                    Text("Most recent update check")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(updaterController.lastCheckDescription)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                */

                Spacer(minLength: 0)
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                await viewModel.refreshContinuityReceipts()
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
            }
        }
    }

    // Used by the dormant direct-distribution Updates card above.
    /*
    private func resultColor(for result: UpdateCheckResult) -> Color {
        switch result {
        case .upToDate:
            return .green
        case .updateAvailable:
            return .blue
        case .error:
            return .orange
        }
    }
    */

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            // Text("Control refresh cadence, notifications, syncing, and updates.")
            Text("Control refresh cadence, notifications, and syncing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Constants.brandPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SettingsTabView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        // .environmentObject(UpdaterController())
        .frame(width: 500, height: 400)
}
#endif
