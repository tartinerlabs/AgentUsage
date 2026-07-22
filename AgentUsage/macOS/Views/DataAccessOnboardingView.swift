//
//  DataAccessOnboardingView.swift
//  AgentUsage
//

#if os(macOS)
import AppKit
import SwiftUI

struct DataAccessOnboardingView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    private let detectsExistingAccess: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var folderAccess = SandboxFolderAccessService.shared
    @State private var connectionState: ContinuityOnboardingMap.State = .idle
    @State private var accessMessage: AccessMessage?

    init(
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        detectsExistingAccess: Bool = true
    ) {
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.detectsExistingAccess = detectsExistingAccess
    }

    var body: some View {
        VStack(spacing: 22) {
            brandHeader
            introduction
            connectionMap
            actions
            privacyNote
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 28)
        .frame(width: 920, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            guard detectsExistingAccess else { return }
            if folderAccess.hasAnyAccess {
                connectionState = .connected
            }
            await monitorFullDiskAccessChanges()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            Image("AgentUsageMark")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(Circle())

            Text(Constants.appDisplayName)
                .font(.largeTitle.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            Text(connectionState == .connected ? "This Mac is connected" : "Your usage, wherever you are")
                .font(.system(.title, design: .default, weight: .bold))
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .accessibilityIdentifier("onboarding.title")

            Text(introductionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)

            Text(connectionState == .connected ? "2 of 2 · Ready" : "1 of 2 · Connect this Mac")
                .font(.caption.weight(.semibold))
                .foregroundStyle(connectionState == .connected ? .green : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .animation(reduceMotion ? nil : .snappy, value: connectionState)
    }

    private var connectionMap: some View {
        VStack(spacing: 14) {
            ContinuityOnboardingMap(
                state: connectionState,
                highlightsMobileDevice: false
            )

            if let accessMessage {
                Label(accessMessage.text, systemImage: accessMessage.systemImage)
                    .font(.caption)
                    .foregroundStyle(accessMessage.color)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .smooth, value: accessMessage)
    }

    @ViewBuilder
    private var actions: some View {
        if connectionState == .connected {
            Button {
                onComplete()
            } label: {
                Text("Continue")
                    .frame(width: 190, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Constants.brandPrimary)
            .keyboardShortcut(.defaultAction)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                Button {
                    chooseHomeFolder()
                } label: {
                    Text("Connect Local Data")
                        .frame(width: 190, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Constants.brandPrimary)
                .keyboardShortcut(.defaultAction)

                Button {
                    onSkip()
                } label: {
                    Text("Skip Setup")
                        .frame(width: 104, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button("Use Full Disk Access instead") {
                folderAccess.requestFullAccess()
                accessMessage = .privacySettingsOpened
                connectionState = .connecting
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Constants.brandPrimary)
        }
    }

    private var privacyNote: some View {
        Label("Local logs never leave this Mac", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var introductionText: String {
        if connectionState == .connected {
            return "AgentUsage can now read local provider data and privately share the latest usage snapshot through your iCloud database."
        }
        return "AgentUsage reads local provider data on this Mac and privately shares the latest usage snapshot through your iCloud database."
    }

    private func chooseHomeFolder() {
        accessMessage = nil
        connectionState = .connecting

        if folderAccess.requestHomeFolderAccess() {
            completeConnection()
        } else {
            connectionState = .idle
            accessMessage = .homeFolderRequired
        }
    }

    private func completeConnection() {
        NotificationCenter.default.post(name: .localDataAccessGranted, object: nil)
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72)) {
            connectionState = .connected
            accessMessage = .connected
        }
    }

    private func monitorFullDiskAccessChanges() async {
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
            folderAccess.refreshAccessStatus()
            if folderAccess.hasAnyAccess, connectionState != .connected {
                completeConnection()
            } else if connectionState == .connecting {
                connectionState = .idle
                accessMessage = .privacySettingsOpened
            }
        }
    }

    private enum AccessMessage: Equatable {
        case homeFolderRequired
        case privacySettingsOpened
        case connected

        var text: String {
            switch self {
            case .homeFolderRequired:
                "Choose your home folder to grant access, or use Full Disk Access instead."
            case .privacySettingsOpened:
                "Enable Agent Usage in Privacy & Security, then return here."
            case .connected:
                "Local data access granted."
            }
        }

        var systemImage: String {
            switch self {
            case .homeFolderRequired: "exclamationmark.triangle.fill"
            case .privacySettingsOpened: "gearshape.fill"
            case .connected: "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .homeFolderRequired: .orange
            case .privacySettingsOpened: Constants.brandPrimary
            case .connected: .green
            }
        }
    }
}
#endif
