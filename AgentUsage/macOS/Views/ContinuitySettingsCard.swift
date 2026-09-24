//
//  ContinuitySettingsCard.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI

struct ContinuitySettingsCard: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var showingRevokeSyncConfirmation = false

    var body: some View {
        settingsCard(title: "Continuity Sync", systemImage: "laptopcomputer.and.iphone") {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    AppConnectionStatusView(
                        status: viewModel.appConnectionStatus,
                        networkStatus: viewModel.continuityNetworkStatus
                    )
                    Spacer(minLength: 12)
                    if viewModel.isRefreshingContinuitySync {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Sync Now") {
                            Task { await viewModel.refreshContinuitySync() }
                        }
                        .disabled(viewModel.appConnectionRevoked || viewModel.snapshot == nil)
                    }
                }

                if !viewModel.removableDeviceLedgers.isEmpty {
                    Divider()
                    otherMacs
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continuity Sync")
                            .font(.body)
                        Text("Control whether this Mac shares \(Constants.appDisplayName) updates with iPhone and iPad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.appConnectionRevoked {
                        Button("Resume Sync") {
                            Task { await viewModel.resumeAppConnection() }
                        }
                    } else {
                        Button("Revoke Sync", role: .destructive) {
                            showingRevokeSyncConfirmation = true
                        }
                        .disabled(viewModel.isRevokingAppConnection)
                    }
                }
            }
        }
        .confirmationDialog("Revoke Sync?", isPresented: $showingRevokeSyncConfirmation, titleVisibility: .visible) {
            Button("Revoke Sync", role: .destructive) {
                Task { await viewModel.revokeAppConnection() }
            }
        } message: {
            Text("This turns off Continuity Sync on this Mac and removes the latest shared update for iPhone and iPad.")
        }
    }

    private var otherMacs: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Other Macs")
                    .font(.body)
                Text("Macs sharing token and cost usage. Remove one that no longer runs \(Constants.appDisplayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.removableDeviceLedgers) { ledger in
                SyncedMacRow(ledger: ledger)
            }
            if let message = viewModel.deviceRemovalErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
