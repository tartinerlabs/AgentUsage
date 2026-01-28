//
//  MenuBarView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI
import ClaudeMeterKit
internal import Combine

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard
    @State private var lastRefreshTap: Date?
    @State private var now = Date()
    private let uiThrottle: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Update banner (if available)
            if updaterController.updateAvailable {
                updateBanner
            }

            // Header
            headerSection

            Divider()
                .padding(.vertical, 8)

            // Content
            if let snapshot = viewModel.snapshot {
                contentSection(snapshot: snapshot)
            } else if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else {
                loadingSection
            }

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionsSection
        }
        .padding(16)
        .frame(width: 300)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Claude")
                    .font(.headline)
                Text(viewModel.planType)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Constants.brandPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Constants.brandPrimary.opacity(0.12))
                    )
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            if let snapshot = viewModel.snapshot {
                Text("Updated \(DateFormatters.relativeDescription(from: snapshot.fetchedAt, to: now))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Content

    private func contentSection(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 16) {
            UsageRowView(title: snapshot.session.windowType.displayName, usage: snapshot.session, now: now)

            // Weekly limits group
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                UsageRowView(title: snapshot.opus.windowType.displayName, usage: snapshot.opus, now: now)
                if let sonnet = snapshot.sonnet {
                    UsageRowView(title: sonnet.windowType.displayName, usage: sonnet, now: now)
                }
            }

            // Token usage section with error/loading states
            tokenUsageSectionWithStates
        }
    }

    // MARK: - Token Usage Section with States

    @ViewBuilder
    private var tokenUsageSectionWithStates: some View {
        if let tokenSnapshot = viewModel.tokenSnapshot {
            tokenCostSection(tokenSnapshot: tokenSnapshot)
        } else if viewModel.isLoadingTokenUsage {
            compactTokenLoadingSection
        } else if let error = viewModel.tokenUsageError {
            compactTokenErrorSection(error: error)
        }
        // If no snapshot, not loading, and no error - silently hide
    }

    private var compactTokenLoadingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("Token Usage & Cost")
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }

    private func compactTokenErrorSection(error: TokenUsageError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)

                Text(error.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await viewModel.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingTokenUsage)
            }
        }
    }

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Token Usage & Cost")
                .font(.callout)
                .fontWeight(.semibold)

            // Today's usage - prominent display
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline) {
                    Text(tokenSnapshot.today.formattedCost)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.brandPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.footnote)
                        Text(tokenSnapshot.today.formattedTokens)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Constants.brandPrimary.opacity(0.08))
            )

            // 30-day usage - prominent display
            VStack(alignment: .leading, spacing: 8) {
                Text("30 Days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline) {
                    Text(tokenSnapshot.last30Days.formattedCost)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.brandPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.footnote)
                        Text(tokenSnapshot.last30Days.formattedTokens)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Constants.brandPrimary.opacity(0.08))
            )
        }
    }

    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView()
            Text("Loading...")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 20)
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)
            Text("Update Available")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
            Button("View") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange)
        )
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            Button {
                let now = Date()
                if let last = lastRefreshTap, now.timeIntervalSince(last) < uiThrottle {
                    return
                }
                lastRefreshTap = now
                Task { await viewModel.refresh(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")

            Spacer()

//            Button {
//                selectedTab = .dashboard
//                openWindow(id: Constants.mainWindowID)
//                NSApp.activate(ignoringOtherApps: true)
//            } label: {
//                Label("Open", systemImage: "macwindow")
//            }
//            .keyboardShortcut("o", modifiers: .command)

            Button {
                selectedTab = .settings
                openWindow(id: Constants.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit (⌘Q)")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

}

#Preview {
    MenuBarView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif

