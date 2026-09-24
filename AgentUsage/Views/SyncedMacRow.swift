//
//  SyncedMacRow.swift
//  AgentUsage
//

import SwiftUI
import AgentUsageKit

/// One Mac sharing local usage through Continuity Sync, with a confirmed
/// Remove action for a Mac that no longer runs AgentUsage.
struct SyncedMacRow: View {
    let ledger: DeviceUsageLedger

    @Environment(UsageViewModel.self) private var viewModel
    @State private var showingRemoveConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ledger.deviceName)
                Text("Updated \(ledger.publishedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if viewModel.removingDeviceIDs.contains(ledger.deviceID) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Remove", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .accessibilityLabel("Remove \(ledger.deviceName)")
            }
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            "Remove \(ledger.deviceName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.removeDevice(ledger) }
            }
        } message: {
            Text("Its token and cost usage leaves the All Macs totals. If \(Constants.appDisplayName) runs on that Mac again, it shares its usage again.")
        }
    }
}
