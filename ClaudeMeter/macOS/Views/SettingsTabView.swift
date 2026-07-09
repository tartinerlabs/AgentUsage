//
//  SettingsTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// Settings content for the main window tab
struct SettingsTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @StateObject private var launchAtLogin = LaunchAtLoginService.shared
    @State private var notificationSettings = NotificationSettings.load()
    @State private var blogSyncTokenDraft = ""

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                settingsCard(title: "General") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .font(.body)
                                Text("Automatically start ClaudeMeter when you log in")
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
                            Text("Which usage windows to show in the menu bar")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("Session (5h)", isOn: $viewModel.menuBarShowSession)
                                Toggle("All Models (7d)", isOn: $viewModel.menuBarShowAllModels)
                                Toggle("Sonnet (7d)", isOn: $viewModel.menuBarShowSonnet)
                                Toggle("Claude Design (7d)", isOn: $viewModel.menuBarShowDesign)
                                Toggle("Fable (7d)", isOn: $viewModel.menuBarShowFable)
                                Toggle("Codex (5h)", isOn: $viewModel.menuBarShowCodex)
                                Toggle("Extra Usage Cost", isOn: $viewModel.menuBarShowExtraUsage)
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

                // Notifications Section
                settingsCard(title: "Notifications") {
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
                            Toggle("", isOn: $viewModel.notificationsEnabled)
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

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Test Notification")
                                        .font(.body)
                                    Text("Send a test notification to verify setup")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Test") {
                                    Task { await NotificationService.shared.sendTestNotification() }
                                }
                            }
                        }
                    }
                }

                // Blog Usage Sync Section
                settingsCard(title: "Blog Usage Sync") {
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

                // OpenCode Go Settings Section
                settingsCard(title: "OpenCode Go") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dashboard Access")
                                .font(.body)
                            Text("Use OpenCode Go's web dashboard to monitor usage and rate-limit windows. Enter your cookie and workspace ID below (see settings → extensions to find these).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Workspace ID")
                                        .font(.body)
                                    Text("Your OpenCode Go workspace ID (the part after /workspace/)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            
                            TextField("wrk_abcdef123456 (or full URL)", text: $viewModel.opencodeGoWorkspaceID)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textCase(.uppercase)
                                .onChange(of: viewModel.opencodeGoWorkspaceID) {
                                    Task { await viewModel.syncOpenCodeGoService() }
                                }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Auth Cookie")
                                        .font(.body)
                                    Text("Session cookie from your browser (starts with \"auth=\")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            
                            SecureField("auth=abcdef123...", text: $viewModel.opencodeGoAuthCookie)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .onChange(of: viewModel.opencodeGoAuthCookie) {
                                    Task { await viewModel.syncOpenCodeGoService() }
                                }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status")
                                        .font(.body)
                                    Text(viewModel.opencodeGoStatusText)
                                        .font(.caption)
                                        .foregroundStyle(viewModel.opencodeGoStatusColor)
                                }
                                Spacer()
                                if viewModel.isOpenCodeGoLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                #if DEBUG
                // Debug Section (only in debug builds)
                settingsCard(title: "Debug") {
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

                // Updates Section
                settingsCard(title: "Updates") {
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

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadBlogUsageSyncSettings()
            blogSyncTokenDraft = viewModel.blogUsageSyncToken
        }
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

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
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
