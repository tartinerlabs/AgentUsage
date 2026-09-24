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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("selectedMainWindowTab") private var selectedTab: NavigationTarget = .section(.dashboard)
    @AppStorage(Constants.commandQClosesWindowKey) private var commandQClosesWindow = false

    @State private var selectedPage: SidebarPage = .overview
    @State private var lastRefreshTap: Date?
    @State private var now = Date()
    /// Natural height of the selected page (padding included); `nil` until measured.
    @State private var pageContentHeight: CGFloat?
    /// Usage-source bar and its divider; zero while the picker is hidden.
    @State private var topChromeHeight: CGFloat = 0
    /// Footer and the divider above it.
    @State private var bottomChromeHeight: CGFloat = 0
    private let uiThrottle: TimeInterval = 5
    private static let scrollTopID = "menuBarPageTop"
    private typealias Layout = MenuBarPopoverLayout

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
        // An explicit height: a `.window` MenuBarExtra sizes to its content, and a
        // ScrollView has no natural height of its own (see `scrollHeight`).
        .frame(width: Layout.width, height: popoverHeight, alignment: .top)
        .task {
            await viewModel.refresh()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private var scrollHeight: CGFloat {
        Layout.scrollHeight(
            pageContentHeight: pageContentHeight,
            chromeHeight: visibleTopChromeHeight + bottomChromeHeight,
            providerCount: availableProviders.count
        )
    }

    private var popoverHeight: CGFloat {
        visibleTopChromeHeight + scrollHeight + bottomChromeHeight
    }

    /// The last measurement lingers after the picker hides, so gate it here.
    private var visibleTopChromeHeight: CGFloat {
        viewModel.showsUsageSourcePicker ? topChromeHeight : 0
    }

    /// Animates later changes; the first measurement lands without animation so
    /// the popover opens at its size.
    private func updatePageContentHeight(_ height: CGFloat) {
        guard let current = pageContentHeight else {
            pageContentHeight = height
            return
        }
        guard abs(current - height) > 0.5 else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            pageContentHeight = height
        }
    }

    // MARK: - Available providers

    private var availableProviders: [Provider] { viewModel.availableProviders }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: Layout.railSpacing) {
            railTab(.overview, tint: .primary) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16))
            }
            ForEach(availableProviders, id: \.self) { provider in
                railTab(.provider(provider), tint: Constants.brandPrimary) {
                    ProviderIcon(provider, size: 16)
                }
            }

            Spacer(minLength: Layout.railSpacerMinLength)

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
        .padding(.vertical, Layout.railVerticalPadding)
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
                .frame(width: 34, height: Layout.railTabHeight)
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
                .frame(width: 34, height: Layout.railActionHeight)
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
                VStack(spacing: 0) {
                    usageSourceBar
                    Divider()
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    topChromeHeight = height
                }
            }

            // A ScrollView has no natural height inside a `.window` MenuBarExtra, so
            // measure the page it holds and give it that height, up to the cap.
            ScrollViewReader { proxy in
                ScrollView {
                    pageContent
                        .padding(16)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            updatePageContentHeight(height)
                        }
                        // Pages shorter than the rail sit at the top, not centred.
                        .frame(minHeight: scrollHeight, alignment: .top)
                        .id(Self.scrollTopID)
                }
                .frame(height: scrollHeight)
                .onChange(of: selectedPage) {
                    proxy.scrollTo(Self.scrollTopID, anchor: .top)
                }
            }

            VStack(spacing: 0) {
                Divider()
                footer
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                bottomChromeHeight = height
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
        // Ticks faster than the page's minute clock so the refresh countdown
        // steps close to its minute boundaries.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack {
                Text("\(Constants.appDisplayName) v\(Bundle.main.appVersion)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let fetchedAt = latestProviderFetchDate {
                    LastUpdatedLabel(
                        relativeText: DateFormatters.relativeDescription(from: fetchedAt, to: context.date),
                        isCached: viewModel.hasStaleProviderStatus,
                        isOffline: viewModel.isOffline,
                        nextRefreshText: nextRefreshText(now: context.date)
                    )
                    .lineLimit(1)
                    .layoutPriority(1)
                }
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            // Room for the spinner at all times, so the footer (and with it the
            // popover height) does not jump when a refresh starts or ends.
            .frame(minHeight: 16)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var isRefreshing: Bool {
        viewModel.isLoading || viewModel.isLoadingTokenUsage
    }

    /// Hidden for Manual, when nothing is scheduled, and while a refresh is running.
    private func nextRefreshText(now: Date) -> String? {
        guard viewModel.refreshInterval != .manual, !isRefreshing else { return nil }
        return RefreshCountdown.text(until: viewModel.nextScheduledRefresh, now: now)
    }

    /// Global freshness reports the most recent visible provider fetch; a provider
    /// with stale data flags itself on its own card.
    private var latestProviderFetchDate: Date? {
        viewModel.availableProviderSnapshots.map(\.fetchedAt).max()
    }
}

/// Sizing for the menu bar popover. The popover fits the selected page, never taller
/// than `maxHeight` (taller pages scroll) and never shorter than the rail.
nonisolated enum MenuBarPopoverLayout {
    static let width: CGFloat = 372
    static let maxHeight: CGFloat = 560

    // Rail metrics, shared by `MenuBarView.rail` and `railMinimumHeight`.
    static let railSpacing: CGFloat = 8
    static let railVerticalPadding: CGFloat = 12
    static let railTabHeight: CGFloat = 30
    static let railActionHeight: CGFloat = 28
    /// Refresh, Settings, and Quit.
    static let railActionCount = 3
    static let railSpacerMinLength: CGFloat = 8

    /// The rail's Overview tab, one tab per provider, and its actions at their fixed
    /// sizes, with the Spacer between them at its minimum length.
    static func railMinimumHeight(providerCount: Int) -> CGFloat {
        let tabs = CGFloat(providerCount + 1)
        let actions = CGFloat(railActionCount)
        let gaps = tabs + actions  // Between tabs, the Spacer, and actions.
        return railVerticalPadding * 2
            + tabs * railTabHeight
            + actions * railActionHeight
            + railSpacerMinLength
            + gaps * railSpacing
    }

    /// Height for the page's ScrollView: the page's natural height, capped so the
    /// popover (page + chrome) stays within `maxHeight`, and floored so the content
    /// column is at least as tall as the rail. An unmeasured page takes the cap.
    static func scrollHeight(
        pageContentHeight: CGFloat?,
        chromeHeight: CGFloat,
        providerCount: Int
    ) -> CGFloat {
        let available = max(maxHeight - chromeHeight, 0)
        let minimum = max(railMinimumHeight(providerCount: providerCount) - chromeHeight, 0)
        let natural = pageContentHeight ?? available
        return max(min(natural, available), minimum)
    }
}

#Preview {
    MenuBarView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        // .environmentObject(UpdaterController())
}
#endif
