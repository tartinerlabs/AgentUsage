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

            // Slim status line
            statusLine

            Divider()
                .padding(.vertical, 8)

            // Provider cards (weather station)
            ScrollView {
                providerCards
            }
            .frame(maxHeight: 520)

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionsSection

            // Version footer
            versionFooter
        }
        .padding(16)
        .frame(width: 320)
        .task {
            // Opening the popover triggers a refresh (rate-limited) so the
            // menu-bar-first experience stays current without the main window.
            await viewModel.refresh()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Status line

    private var statusLine: some View {
        HStack(spacing: 8) {
            if let snapshot = viewModel.snapshot {
                Text("Updated \(DateFormatters.relativeDescription(from: snapshot.fetchedAt, to: now))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("ClaudeMeter")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if viewModel.isLoading || viewModel.isLoadingTokenUsage {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Spacer()
        }
    }

    // MARK: - Provider cards

    @ViewBuilder
    private var providerCards: some View {
        VStack(spacing: 12) {
            // Claude
            if let snapshot = viewModel.snapshot {
                claudeCard(snapshot)
            } else if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else {
                loadingSection
            }

            // Codex (rate-limit windows + cost)
            if let codex = viewModel.codexUsage {
                codexCard(codex)
            }

            // OpenCode (cost only)
            if let openCode = viewModel.extraProviderSummaries[.openCode] {
                ProviderCardView(
                    provider: .openCode,
                    costLines: costLines(openCode),
                    now: now,
                    showExtraUsage: false,
                    compact: true
                )
            }
        }
    }

    private func claudeCard(_ snapshot: UsageSnapshot) -> some View {
        let lines: [ProviderCostLine] = viewModel.tokenSnapshot.map {
            [
                ProviderCostLine(label: "Today", cost: $0.today.formattedCost, tokens: $0.today.formattedTokens),
                ProviderCostLine(label: "30 Days", cost: $0.last30Days.formattedCost, tokens: $0.last30Days.formattedTokens)
            ]
        } ?? []

        return ProviderCardView(
            provider: .claude,
            planName: viewModel.planType,
            windows: ProviderUsageSnapshot(claude: snapshot).windows,
            extraUsage: viewModel.showExtraUsageIndicators ? snapshot.extraUsage : nil,
            costLines: lines,
            now: now,
            showExtraUsage: viewModel.showExtraUsageIndicators,
            compact: true
        )
    }

    private func codexCard(_ codex: ProviderUsageSnapshot) -> some View {
        let lines = viewModel.extraProviderSummaries[.codex].map(costLines) ?? []
        return ProviderCardView(
            provider: .codex,
            planName: codex.planName,
            windows: codex.windows,
            costLines: lines,
            now: now,
            showExtraUsage: false,
            compact: true
        )
    }

    private func costLines(_ breakdown: ProviderTokenBreakdown) -> [ProviderCostLine] {
        [
            ProviderCostLine(label: "Today", cost: breakdown.today.formattedCost, tokens: breakdown.today.formattedTokens),
            ProviderCostLine(label: "30 Days", cost: breakdown.last30Days.formattedCost, tokens: breakdown.last30Days.formattedTokens)
        ]
    }

    // MARK: - States

    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Version

    private var versionFooter: some View {
        HStack {
            Spacer()
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.top, 4)
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
