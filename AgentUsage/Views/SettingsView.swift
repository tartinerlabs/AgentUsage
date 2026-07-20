//
//  SettingsView.swift
//  AgentUsage
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

            NotificationsTab()
                .environment(viewModel)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            if Bundle.main.isAppStoreBuild {
                UpdatesTab()
                    .environmentObject(updaterController)
                    .tabItem {
                        Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
            }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 340)
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications Tab

private struct NotificationsTab: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var settings = NotificationSettings.load()

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Enable Notifications", isOn: notificationsEnabledBinding)
            }

            if viewModel.notificationsEnabled {
                Section("Alert Thresholds") {
                    ForEach(NotificationSettings.availableThresholds, id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: Binding(
                            get: { settings.isThresholdEnabled(threshold) },
                            set: { _ in
                                settings.toggleThreshold(threshold)
                                settings.save()
                            }
                        ))
                    }
                }

                Section("Usage Types") {
                    Toggle("Session (5-hour)", isOn: Binding(
                        get: { settings.notifySession },
                        set: { settings.notifySession = $0; settings.save() }
                    ))
                    Toggle("All Models (weekly)", isOn: Binding(
                        get: { settings.notifyOpus },
                        set: { settings.notifyOpus = $0; settings.save() }
                    ))
                    Toggle("Sonnet (weekly)", isOn: Binding(
                        get: { settings.notifySonnet },
                        set: { settings.notifySonnet = $0; settings.save() }
                    ))
                    Toggle("Claude Design (weekly)", isOn: Binding(
                        get: { settings.notifyDesign },
                        set: { settings.notifyDesign = $0; settings.save() }
                    ))
                    Toggle("Fable (weekly)", isOn: Binding(
                        get: { settings.notifyFable },
                        set: { settings.notifyFable = $0; settings.save() }
                    ))
                }

                Section {
                    Toggle("Notify on Reset", isOn: Binding(
                        get: { settings.notifyOnReset },
                        set: { settings.notifyOnReset = $0; settings.save() }
                    ))
                    .help("Get notified when your usage limit resets after being near capacity")

                    Toggle("Extra Usage Alert", isOn: Binding(
                        get: { settings.notifyExtraUsage },
                        set: { settings.notifyExtraUsage = $0; settings.save() }
                    ))
                    .help("Get notified when extra usage starts. Requires extra usage to be enabled in your Claude account.")
                }

            }

            Section {
                Button("Send Test Notification") {
                    Task { await viewModel.sendTestNotification() }
                }
                notificationTestStatus
            } footer: {
                Text("Uses synthetic content and does not require usage data.")
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.notificationsEnabled },
            set: { enabled in
                Task { await viewModel.setNotificationsEnabled(enabled) }
            }
        )
    }

    @ViewBuilder
    private var notificationTestStatus: some View {
        switch viewModel.notificationTestResult {
        case .some(.sent):
            EmptyView()
        case .some(.permissionDenied):
            Label("Notifications are disabled in System Settings.", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        case .some(.failed(let message)):
            Label("Could not send the test: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Updates Tab

private struct UpdatesTab: View {
    @EnvironmentObject private var updaterController: UpdaterController

    var body: some View {
        Form {
            Toggle("Automatic Updates", isOn: Binding(
                get: { updaterController.automaticallyChecksForUpdates },
                set: { updaterController.automaticallyChecksForUpdates = $0 }
            ))

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Check for Updates") {
                if updaterController.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else if let result = updaterController.lastCheckResult {
                    HStack(spacing: 4) {
                        Image(systemName: result.systemImage)
                            .foregroundStyle(resultColor(for: result))
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Check Now") {
                        updaterController.checkForUpdates()
                    }
                    .disabled(!updaterController.canCheckForUpdates)
                }
            }

            Divider()
                .padding(.vertical, 4)

            LabeledContent("Version", value: Bundle.main.appVersion)
        }
        .formStyle(.grouped)
    }

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
                Text(Constants.appDisplayName)
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
                Link(destination: URL(string: "https://github.com/tartinerlabs/AgentUsage")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/tartinerlabs/AgentUsage/issues")!) {
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

    /// True only when distributed through App Store Connect (Mac App Store or
    /// TestFlight), detected by the presence of an App Store receipt.
    /// Developer ID / direct-download / ad-hoc / dev builds have no receipt.
    var isAppStoreBuild: Bool {
        guard let receiptURL = appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}

#Preview {
    SettingsView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif
