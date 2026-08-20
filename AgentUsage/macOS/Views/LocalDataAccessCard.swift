//
//  LocalDataAccessCard.swift
//  AgentUsage
//

#if os(macOS)
import AgentUsageKit
import SwiftUI

struct LocalDataAccessCard: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var folderAccess = SandboxFolderAccessService.shared

    var body: some View {
        settingsCard(title: "Local Data Access", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "\(Constants.appDisplayName) runs sandboxed, so macOS blocks direct reads "
                        + "from the folders where Claude, Codex, OpenCode, Cursor, and Grok keep local "
                        + "usage logs or session state. Grant your home folder here, or use Full Disk Access in Privacy & Security as a fallback."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    localDataAccessStatusLabel

                    Spacer()

                    Button("Check Again") {
                        refreshAfterAccessChange()
                    }

                    Button("Open Privacy Settings") {
                        folderAccess.requestFullAccess()
                    }

                    Button("Choose Home Folder") {
                        if folderAccess.requestHomeFolderAccess() {
                            NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
                            Task { _ = await viewModel.refresh(force: true) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reads")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(SandboxFolderAccessService.grantableProviders) { provider in
                        HStack(spacing: 6) {
                            Label(provider)
                                .font(.caption)
                            Text(folderAccess.defaultDirectory(for: provider).path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var localDataAccessStatusLabel: some View {
        Group {
            if folderAccess.hasFullAccess {
                Label("Full Disk Access enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if folderAccess.hasHomeFolderAccess {
                Label("Home folder access saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if folderAccess.hasAnyAccess {
                Label("Saved folder access available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Access needed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func refreshAfterAccessChange() {
        folderAccess.refreshAccessStatus()
        if folderAccess.hasAnyAccess {
            NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
            Task { _ = await viewModel.refresh(force: true) }
        }
    }
}
#endif
