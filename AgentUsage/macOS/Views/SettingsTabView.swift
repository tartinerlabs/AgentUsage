//
//  SettingsTabView.swift
//  AgentUsage
//

#if os(macOS)
import AgentUsageKit
import AppKit
import SwiftUI

/// Settings content for the main window tab
struct SettingsTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @StateObject private var launchAtLogin = LaunchAtLoginService.shared
    @State private var notificationSettings = NotificationSettings.load()
    @State private var blogSyncTokenDraft = ""
    @State private var folderAccess = SandboxFolderAccessService.shared
    @State private var showingRevokeSyncConfirmation = false

    private let contentWidth: CGFloat = 760

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader

                // Continuity Sync Section
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

                // General Section
                settingsCard(title: "General", systemImage: "gearshape") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .font(.body)
                                Text("Automatically start \(Constants.appDisplayName) when you log in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $launchAtLogin.isEnabled)
                                .labelsHidden()
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Refresh Interval")
                                    .font(.body)
                                Text("How often to fetch usage data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $viewModel.refreshInterval) {
                                ForEach(RefreshFrequency.allCases) { frequency in
                                    Text(frequency.displayName).tag(frequency)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Menu Bar Display")
                                .font(.body)
                            Text("Pin up to two quota windows per provider. Providers without live pinned data take no space.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(viewModel.menuBarProviders) { provider in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(provider.displayName, systemImage: provider.iconName)
                                                .font(.caption.weight(.semibold))
                                            Spacer()
                                            Text("\(viewModel.menuBarPinnedWindows(for: provider).count)/\(MenuBarSettingsManager.maximumPinsPerProvider)")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.tertiary)
                                        }

                                        ForEach(
                                            viewModel.menuBarSupportedWindows(for: provider),
                                            id: \.rawValue
                                        ) { window in
                                            let isPinned = viewModel.isMenuBarWindowPinned(
                                                window,
                                                for: provider
                                            )
                                            Toggle(
                                                window.displayName,
                                                isOn: menuBarPinBinding(window, provider: provider)
                                            )
                                            .disabled(
                                                !isPinned
                                                    && !viewModel.canPinMenuBarWindow(
                                                        window,
                                                        for: provider
                                                    )
                                            )
                                        }
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.top, 4)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Extra Usage Indicators")
                                    .font(.body)
                                Text("Show extra usage badges, banners, and cost sections. Requires extra usage to be enabled in your Claude account.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.showExtraUsageIndicators)
                                .labelsHidden()
                        }
                    }
                }

                localDataAccessCard

                // Notifications Section
                settingsCard(title: "Notifications", systemImage: "bell.badge") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Usage Alerts")
                                    .font(.body)
                                Text("Notify when usage crosses 25%, 50%, 75%, or 100%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: notificationsEnabledBinding)
                                .labelsHidden()
                        }

                        if viewModel.notificationsEnabled {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Extra Usage Alert")
                                        .font(.body)
                                    Text("Notify when extra usage starts (plan limit exceeded). Requires extra usage to be enabled in your Claude account.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { notificationSettings.notifyExtraUsage },
                                    set: {
                                        notificationSettings.notifyExtraUsage = $0
                                        notificationSettings.save()
                                    }
                                ))
                                .labelsHidden()
                            }

                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Test Notification")
                                    .font(.body)
                                Text("Uses synthetic content and does not require usage data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Test") {
                                Task { await viewModel.sendTestNotification() }
                            }
                        }

                        notificationTestStatus
                    }
                }

                // Blog Usage Sync Section
                settingsCard(title: "Blog Usage Sync", systemImage: "arrow.triangle.2.circlepath") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Sync")
                                    .font(.body)
                                Text("Passively sync daily Claude, Codex, and OpenCode Go usage to the blog backend")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.blogUsageSyncEnabled)
                                .labelsHidden()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Endpoint URL")
                                .font(.body)
                            TextField("Endpoint URL", text: $viewModel.blogUsageSyncEndpointURLString)
                                .textFieldStyle(.roundedBorder)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Blog Account")
                                        .font(.body)
                                    if viewModel.isBlogSignedIn {
                                        Text(viewModel.blogOAuthAccountEmail ?? "Signed in")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Sign in to authenticate sync with OAuth")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if viewModel.isBlogSigningIn {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                if viewModel.isBlogSignedIn {
                                    Button("Sign Out") {
                                        Task { await viewModel.signOutOfBlog() }
                                    }
                                    .disabled(viewModel.isBlogSigningIn)
                                } else {
                                    Button("Sign in to blog") {
                                        Task { await viewModel.signInToBlog() }
                                    }
                                    .disabled(viewModel.isBlogSigningIn)
                                }
                            }
                            if let blogOAuthError = viewModel.blogOAuthError {
                                Text(blogOAuthError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fallback token (used when not signed in)")
                                .font(.body)
                            HStack {
                                SecureField("BLOG_MCP_AUTH_TOKEN", text: $blogSyncTokenDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        Task { await viewModel.saveBlogUsageSyncToken(blogSyncTokenDraft) }
                                    }
                                Button("Save") {
                                    Task { await viewModel.saveBlogUsageSyncToken(blogSyncTokenDraft) }
                                }
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Sync")
                                    .font(.body)
                                Text(blogUsageSyncStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.isBlogUsageSyncing || viewModel.blogUsageSyncStatus.state == .syncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button("Sync Now") {
                                Task { await viewModel.syncBlogUsageNow() }
                            }
                            .disabled(viewModel.isBlogUsageSyncing)
                        }
                    }
                }

                #if DEBUG
                // Debug Section (only in debug builds)
                settingsCard(title: "Debug", systemImage: "ladybug") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Simulate 100% Usage")
                                    .font(.body)
                                Text("Show countdown in menu bar as if at limit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.debugSimulate100Percent)
                                .labelsHidden()
                        }

                        if viewModel.debugSimulate100Percent {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Test Reset Notification")
                                        .font(.body)
                                    Text("Simulate a usage window reset")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Send") {
                                    Task { await NotificationService.shared.sendTestResetNotification() }
                                }
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Force Background Check")
                                    .font(.body)
                                Text("Trigger a silent update check")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Check") {
                                updaterController.checkForUpdatesInBackground()
                            }
                        }
                    }
                }
                #endif

                // Updates Section (App Store Connect builds only)
                if Bundle.main.isAppStoreBuild {
                    settingsCard(title: "Updates", systemImage: "arrow.down.circle") {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current Version")
                                        .font(.body)
                                    Text("Installed app version")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Bundle.main.appVersion)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Automatic Updates")
                                        .font(.body)
                                    Text("Check for updates automatically")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { updaterController.automaticallyChecksForUpdates },
                                    set: { updaterController.automaticallyChecksForUpdates = $0 }
                                ))
                                .labelsHidden()
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Check for Updates")
                                        .font(.body)
                                    Text("Download and install the latest version")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                if let result = updaterController.lastCheckResult {
                                    HStack(spacing: 4) {
                                        Image(systemName: result.systemImage)
                                            .foregroundStyle(resultColor(for: result))
                                        Text(result.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                if updaterController.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Check Now") {
                                        updaterController.checkForUpdates()
                                    }
                                    .disabled(!updaterController.canCheckForUpdates)
                                }
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Checked")
                                        .font(.body)
                                    Text("Most recent update check")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(updaterController.lastCheckDescription)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadBlogUsageSyncSettings()
            blogSyncTokenDraft = viewModel.blogUsageSyncToken
        }
        .task {
            while !Task.isCancelled {
                await viewModel.refreshContinuityReceipts()
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
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

    private func menuBarPinBinding(
        _ window: UsageWindowType,
        provider: Provider
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.isMenuBarWindowPinned(window, for: provider) },
            set: { viewModel.setMenuBarWindowPinned(window, for: provider, isPinned: $0) }
        )
    }

    private var blogUsageSyncStatusText: String {
        let status = viewModel.blogUsageSyncStatus
        var parts = [status.message]
        if let lastAttemptAt = status.lastAttemptAt {
            parts.append("Last attempt \(lastAttemptAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let lastSuccessAt = status.lastSuccessAt {
            parts.append("Last success \(lastSuccessAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " • ")
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

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Text("Control refresh cadence, notifications, syncing, and updates.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var localDataAccessCard: some View {
        settingsCard(title: "Local Data Access", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "\(Constants.appDisplayName) runs sandboxed, so macOS blocks direct reads "
                        + "from the hidden folders where Claude, Codex, and OpenCode keep local "
                        + "usage logs. Grant your home folder here, or use Full Disk Access in Privacy & Security as a fallback."
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
                            Label(provider.displayName, systemImage: provider.iconName)
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

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Constants.brandPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SettingsTabView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
        .frame(width: 500, height: 400)
}
#endif
