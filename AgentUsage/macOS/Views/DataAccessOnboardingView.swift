//
//  DataAccessOnboardingView.swift
//  AgentUsage
//
//  First-run sheet requesting user-granted access so the sandboxed app can read
//  local CLI usage logs.
//

#if os(macOS)
import SwiftUI
import AgentUsageKit

extension Notification.Name {
    /// Posted after the user grants local data access, so live views can refresh.
    static let localDataAccessGranted = Notification.Name("localDataAccessGranted")
}

struct DataAccessOnboardingView: View {
    /// Invoked to dismiss the hosting window, whether the user opens Settings or skips.
    let onClose: () -> Void

    @State private var folderAccess = SandboxFolderAccessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(Constants.brandPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Local Data Access")
                        .font(.title2.weight(.semibold))
                    Text("Choose your home folder; Full Disk Access is optional")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "\(Constants.appDisplayName) runs sandboxed, so macOS blocks direct reads from "
                    + "the hidden folders where Claude, Codex, and OpenCode keep local usage logs. "
                    + "Grant your home folder here, or use Full Disk Access in Privacy & Security as a fallback."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SandboxFolderAccessService.grantableProviders) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .font(.callout)
                }
            }
            .padding(.leading, 2)

            Spacer(minLength: 0)

            HStack {
                Button("Not Now") {
                    onClose()
                }
                Spacer()
                Button("Open Privacy Settings") {
                    folderAccess.requestFullAccess()
                    onClose()
                }
                Button("Choose Home Folder") {
                    if folderAccess.requestHomeFolderAccess() {
                        NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
                    }
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440, height: 320)
    }
}
#endif
