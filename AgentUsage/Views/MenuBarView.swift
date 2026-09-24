//
//  MenuBarView.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI
import AgentUsageKit
internal import Combine

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel
    // Direct-distribution updater support is dormant while releases use App Store/TestFlight.
    // @EnvironmentObject private var updaterController: UpdaterController
    @Environment(\.openWindow) private var openWindow
    @AppStorage("selectedMainWindowTab") private var selectedTab: NavigationTarget = .section(.dashboard)
    @AppStorage(Constants.commandQClosesWindowKey) private var commandQClosesWindow = false

    @State private var selectedPage: SidebarPage = .overview
    @State private var lastRefreshTap: Date?
    @State private var now = Date()
    private let uiThrottle: TimeInterval = 5

    private enum SidebarPage: Hashable {
        case overview
        case provider(Provider)

        var accessibilityLabel: String {
            switch self {
            case .overview:
                "Overview"
            case .provider(let provider):
                provider.displayName
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            content
        }
        .frame(width: 372, height: 560)
        .task {
            await viewModel.refresh()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Available providers

    private var availableProviders: [Provider] { viewModel.availableProviders }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: 8) {
            railTab(.overview, tint: .primary) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16))
            }
            ForEach(availableProviders, id: \.self) { provider in
                railTab(.provider(provider), tint: Constants.brandPrimary) {
                    ProviderIcon(provider, size: 16)
                }
            }

            Spacer()

            railAction("arrow.clockwise", help: "Refresh (⌘R)", key: "r") {
                let tapped = Date()
                if let last = lastRefreshTap, tapped.timeIntervalSince(last) < uiThrottle { return }
                lastRefreshTap = tapped
                Task { await viewModel.refresh(force: true) }
            }
            railAction("gear", help: "Settings (⌘,)", key: ",") {
                selectedTab = .section(.settings)
                openWindow(id: Constants.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            railAction(
                "power",
                help: commandQClosesWindow ? "Quit" : "Quit (⌘Q)",
                key: commandQClosesWindow ? nil : "q"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .background { closeWindowShortcut }
    }

    /// The popover is its own key window, so the app menu's ⌘Q does not reach it.
    @ViewBuilder
    private var closeWindowShortcut: some View {
        if commandQClosesWindow {
            Button("Close Window") {
                AppDelegate.closeMainWindows()
            }
            .keyboardShortcut("q", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func railTab<Icon: View>(
        _ page: SidebarPage,
        tint: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let isSelected = selectedPage == page
        return Button {
            selectedPage = page
        } label: {
            icon()
                .foregroundStyle(isSelected ? tint : .secondary)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? tint.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func railAction(
        _ systemImage: String,
        help: String,
        key: KeyEquivalent?,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)

        // The popover is its own key window, so the app's main-menu shortcuts do not
        // reach it. Bind them here to match what each tooltip advertises.
        if let key {
            button.keyboardShortcut(key, modifiers: .command)
        } else {
            button
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Restore with the updater integration for a future direct-distribution build.
            /*
            if updaterController.updateAvailable {
                updateBanner.padding([.horizontal, .top], 16)
            }
            */

            if viewModel.showsUsageSourcePicker {
                usageSourceBar
                Divider()
            }

            ScrollView {
                pageContent
                    .padding(16)
            }

            Divider()
            footer
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .overview:
            overviewPage
        case .provider(let provider):
            ProviderCardView(
                provider: provider,
                planName: viewModel.usageSnapshot(for: provider)?.planName,
                windows: viewModel.usageSnapshot(for: provider)?.windows ?? [],
                extraUsage: viewModel.usageSnapshot(for: provider)?.extraUsage,
                now: now,
                showExtraUsage: viewModel.showExtraUsageIndicators,
                compact: true,
                status: viewModel.status(for: provider, now: now),
                fetchedAt: viewModel.usageSnapshot(for: provider)?.fetchedAt,
                rateLimitResetCredits: viewModel.usageSnapshot(for: provider)?.rateLimitResetCredits,
                density: .detail,
                detail: viewModel.providerDetail(for: provider),
                effortSummaries: viewModel.effortSummaries(for: provider),
                effortPeriod: viewModel.selectedTokenPeriod.effortPeriod,
                usageBreakdown: viewModel.usageSnapshot(for: provider)?.usageBreakdown ?? []
            )
        }
    }

    @ViewBuilder
    private var overviewPage: some View {
        let providers = availableProviders
        if providers.isEmpty {
            if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else if viewModel.isNoUsageData {
                noUsageSection
            } else {
                loadingSection
            }
        } else {
            // Each card carries its own status, so a stale or failing provider is
            // flagged on its card rather than in an app-wide banner.
            VStack(spacing: 12) {
                ForEach(providers, id: \.self) { provider in
                    overviewCard(provider)
                }
            }
        }
    }

    private func overviewCard(_ provider: Provider) -> some View {
        ProviderCardView(
            provider: provider,
            planName: viewModel.usageSnapshot(for: provider)?.planName,
            windows: viewModel.usageSnapshot(for: provider)?.windows ?? [],
            extraUsage: viewModel.showExtraUsageIndicators
                ? viewModel.usageSnapshot(for: provider)?.extraUsage
                : nil,
            costLines: costLines(for: provider),
            now: now,
            showExtraUsage: viewModel.showExtraUsageIndicators,
            compact: true,
            status: viewModel.status(for: provider, now: now),
            fetchedAt: viewModel.usageSnapshot(for: provider)?.fetchedAt,
            rateLimitResetCredits: viewModel.usageSnapshot(for: provider)?.rateLimitResetCredits
        )
    }

    // MARK: - Per-provider data

    private func costLines(for provider: Provider) -> [ProviderCostLine] {
        guard let detail = viewModel.providerDetail(for: provider), detail.hasTokenUsage else { return [] }
        return [
            ProviderCostLine(label: "Today", cost: detail.today.formattedCost, tokens: detail.today.formattedTokens),
            ProviderCostLine(label: "30 Days", cost: detail.last30Days.formattedCost, tokens: detail.last30Days.formattedTokens)
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

    private var noUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No usage data", systemImage: "chart.bar.xaxis")
            Text("Usage limits will appear when a connected provider reports a new window.")
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
        .padding(.vertical, 40)
    }

    // Restore with the updater integration for a future direct-distribution build.
    /*
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
    }
    */

    /// Scopes token and cost lines on every page; quota windows are account-wide.
    private var usageSourceBar: some View {
        HStack {
            Spacer(minLength: 0)
            UsageSourcePicker()
                .controlSize(.small)
                .fixedSize()
                .help("Token and cost usage from every Mac, or one Mac")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Text("\(Constants.appDisplayName) v\(Bundle.main.appVersion)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if let fetchedAt = latestProviderFetchDate {
                LastUpdatedLabel(
                    relativeText: DateFormatters.relativeDescription(from: fetchedAt, to: now),
                    isCached: viewModel.hasStaleProviderStatus,
                    isOffline: viewModel.isOffline
                )
            }
            if viewModel.isLoading || viewModel.isLoadingTokenUsage {
                ProgressView().scaleEffect(0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Global freshness reports the most recent visible provider fetch; a provider
    /// with stale data flags itself on its own card.
    private var latestProviderFetchDate: Date? {
        viewModel.availableProviderSnapshots.map(\.fetchedAt).max()
    }
}

#Preview {
    MenuBarView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        // .environmentObject(UpdaterController())
}
#endif
