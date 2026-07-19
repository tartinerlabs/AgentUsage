//
//  SettingsView+iOS.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI

/// iOS Settings view
struct SettingsView: View {
    @Environment(UsageViewModel.self) private var viewModel
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
                Toggle("Extra Usage Indicators", isOn: $viewModel.showExtraUsageIndicators)
            } header: {
                Text("Display")
            } footer: {
                Text("Show extra usage badges, banners, and cost sections throughout the app. Requires extra usage to be enabled in your Claude account.")
            }

            Section("Continuity Sync") {
                AppConnectionStatusView(status: viewModel.appConnectionStatus)

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

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Revoke Sync?", isPresented: $showingRevokeSyncConfirmation, titleVisibility: .visible) {
            Button("Revoke Sync", role: .destructive) {
                Task { await viewModel.revokeAppConnection() }
            }
        } message: {
            Text("This turns off Continuity Sync for this device and clears shared app data from this device.")
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
