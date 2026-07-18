//
//  DataAccessOnboardingView.swift
//  AgentUsage
//
//  First-run sheet asking, once, for the single home-folder grant that lets the
//  sandboxed app read the CLI tools' local usage logs.
//

#if os(macOS)
import SwiftUI
import AgentUsageKit

extension Notification.Name {
    /// Posted after the user grants local data access, so live views can refresh.
    static let localDataAccessGranted = Notification.Name("localDataAccessGranted")
}

struct DataAccessOnboardingView: View {
    /// Invoked to dismiss the hosting window, whether the user grants or skips.
    let onClose: () -> Void

    @State private var folderAccess = SandboxFolderAccessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.largeTitle)
                    .foregroundStyle(Constants.brandPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Local Data Access")
                        .font(.title2.weight(.semibold))
                    Text("Asked only once")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "\(Constants.appDisplayName) runs sandboxed, so it needs your permission to read "
                    + "your home folder, where each tool keeps its local usage logs. One grant "
                    + "covers token usage, cost, and blog sync for all supported tools."
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
                Button("Grant Access…") {
                    if folderAccess.requestFullAccess() {
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
