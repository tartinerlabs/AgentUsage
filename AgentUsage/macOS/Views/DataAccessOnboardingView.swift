//
//  DataAccessOnboardingView.swift
//  AgentUsage
//
//  First-run sheet requesting user-granted access so the sandboxed app can read
//  local CLI usage logs.
//

#if os(macOS)
import AppKit
import SwiftUI
import AgentUsageKit

extension Notification.Name {
    /// Posted after the user grants local data access, so live views can refresh.
    static let localDataAccessGranted = Notification.Name("localDataAccessGranted")
}

struct DataAccessOnboardingView: View {
    /// Invoked to dismiss the hosting window after the user completes or skips onboarding.
    let onClose: () -> Void

    @State private var folderAccess = SandboxFolderAccessService.shared
    @State private var accessMessage: AccessMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            explanation
            providersPreview

            if let accessMessage {
                statusMessage(accessMessage)
            }

            Spacer(minLength: 0)
            actions
        }
        .padding(28)
        .frame(width: 480, height: 360)
        .task {
            await monitorFullDiskAccessChanges()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(Constants.brandPrimary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Local Usage Logs")
                    .font(.title2.weight(.semibold))
                Text("One folder grant unlocks Claude, Codex, and OpenCode history")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explanation: some View {
        Text(
            "\(Constants.appDisplayName) runs sandboxed. Choose your home folder to save a secure read grant for the hidden log folders below. Full Disk Access remains available as a fallback from Privacy & Security."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var providersPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(SandboxFolderAccessService.grantableProviders) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(provider.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(provider.accentColor.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(provider.accentColor.opacity(0.15), lineWidth: 1)
                        )
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Not Now") {
                onClose()
            }

            Spacer()

            if accessMessage == .privacySettingsOpened {
                Button("Check Again") {
                    refreshAndCloseIfGranted()
                }
            }

            Button("Open Privacy Settings") {
                folderAccess.requestFullAccess()
                accessMessage = .privacySettingsOpened
            }

            Button("Choose Home Folder") {
                chooseHomeFolder()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func statusMessage(_ message: AccessMessage) -> some View {
        Label(message.text, systemImage: message.systemImage)
            .font(.caption)
            .foregroundStyle(message.color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(message.color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(message.color.opacity(0.16), lineWidth: 1)
            )
    }

    private func chooseHomeFolder() {
        if folderAccess.requestHomeFolderAccess() {
            NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
            onClose()
        } else {
            accessMessage = .homeFolderRequired
        }
    }

    private func refreshAndCloseIfGranted() {
        folderAccess.refreshAccessStatus()
        if folderAccess.hasAnyAccess {
            NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
            onClose()
        } else {
            accessMessage = .privacySettingsOpened
        }
    }

    private func monitorFullDiskAccessChanges() async {
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
            refreshAndCloseIfGranted()
        }
    }

    private enum AccessMessage: Equatable {
        case homeFolderRequired
        case privacySettingsOpened

        var text: String {
            switch self {
            case .homeFolderRequired:
                "Choose your home folder to finish setup. The grant is only saved after macOS returns that exact folder."
            case .privacySettingsOpened:
                "After enabling Full Disk Access in System Settings, return here and Agent Usage will check again."
            }
        }

        var systemImage: String {
            switch self {
            case .homeFolderRequired:
                "exclamationmark.triangle.fill"
            case .privacySettingsOpened:
                "gearshape.fill"
            }
        }

        var color: Color {
            switch self {
            case .homeFolderRequired:
                .orange
            case .privacySettingsOpened:
                Constants.brandPrimary
            }
        }
    }
}
#endif
