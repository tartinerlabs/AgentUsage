//
//  SettingsView+iOS.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI
import UIKit

/// iOS Settings view
struct SettingsView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationSettings = NotificationSettings.load()
    @State private var showingRevokeSyncConfirmation = false
    @State private var showingRevokeSyncPopover = false

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

            Section {
                Toggle(isOn: notificationsEnabledBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage Alerts")
                        Text("Notify when usage crosses 25%, 50%, 75%, or 100%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.notificationPermissionState == .denied {
                    Label("Notifications are disabled in iOS Settings", systemImage: "bell.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Open Settings") {
                        openSystemSettings()
                    }
                } else {
                    if viewModel.notificationsEnabled {
                        Toggle("Extra Usage Alert", isOn: Binding(
                            get: { notificationSettings.notifyExtraUsage },
                            set: {
                                notificationSettings.notifyExtraUsage = $0
                                notificationSettings.save()
                            }
                        ))
                    }

                    Button("Send Test Notification") {
                        Task { await viewModel.sendTestNotification() }
                    }

                    notificationTestStatus
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Usage alerts are delivered when this device refreshes usage shared by your Mac. Test notifications use synthetic content and do not require synced usage data.")
            }

            Section {
                Toggle("Extra Usage Indicators", isOn: $viewModel.showExtraUsageIndicators)
            } header: {
                Text("Display")
            } footer: {
                Text("Show extra usage badges, banners, and cost sections throughout the app. Requires extra usage to be enabled in your Claude account.")
            }

            Section("Continuity Sync") {
                AppConnectionStatusView(
                    status: viewModel.appConnectionStatus,
                    networkStatus: viewModel.continuityNetworkStatus
                )

                if viewModel.appConnectionRevoked {
                    Button {
                        Task { await viewModel.resumeAppConnection() }
                    } label: {
                        Label("Resume Sync", systemImage: "link")
                    }
                } else {
                    revokeSyncButton
                }
            }

            Section {
                Label("Mac keeps this device up to date", systemImage: "laptopcomputer.and.iphone")
                Text("Open \(Constants.appDisplayName) on your Mac to share the latest usage with this device through iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Continuity")
            }

            Section("Setup") {
                Button {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                } label: {
                    Label("Run Setup Again", systemImage: "sparkles")
                }
            }

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshNotificationPermissionState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.refreshNotificationPermissionState() }
        }
        .confirmationDialog("Revoke Sync?", isPresented: $showingRevokeSyncConfirmation, titleVisibility: .visible) {
            Button("Revoke Sync", role: .destructive) {
                Task { await viewModel.revokeAppConnection() }
            }
        } message: {
            Text("This turns off Continuity Sync for this device and clears shared app data from this device.")
        }
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.notificationsEnabled },
            set: { enabled in
                Task { await viewModel.setNotificationsEnabled(enabled) }
            }
        )
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    @ViewBuilder
    private var notificationTestStatus: some View {
        switch viewModel.notificationTestResult {
        case .some(.sent):
            EmptyView()
        case .some(.permissionDenied):
            Label("Notifications are disabled in iOS Settings.", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        case .some(.failed(let message)):
            Label("Could not send the test: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var revokeSyncButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .destructive) {
                showingRevokeSyncPopover = true
            } label: {
                Label("Revoke Sync", systemImage: "link.badge.minus")
            }
            .disabled(viewModel.isRevokingAppConnection)
            .popover(
                isPresented: $showingRevokeSyncPopover,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                RevokeSyncConfirmationPopover(
                    isRevoking: viewModel.isRevokingAppConnection,
                    onCancel: { showingRevokeSyncPopover = false },
                    onRevoke: {
                        showingRevokeSyncPopover = false
                        Task { await viewModel.revokeAppConnection() }
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        } else {
            Button(role: .destructive) {
                showingRevokeSyncConfirmation = true
            } label: {
                Label("Revoke Sync", systemImage: "link.badge.minus")
            }
            .disabled(viewModel.isRevokingAppConnection)
        }
    }
}

private struct RevokeSyncConfirmationPopover: View {
    let isRevoking: Bool
    let onCancel: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Revoke Sync?")
                    .font(.headline)
                Text("This turns off Continuity Sync for this device and clears shared app data from this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .disabled(isRevoking)

                Button(role: .destructive) {
                    onRevoke()
                } label: {
                    if isRevoking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Revoke Sync")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isRevoking)
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
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
