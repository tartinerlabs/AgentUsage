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

    @State private var selectedPage: SidebarPage = .overview
    @State private var lastRefreshTap: Date?
    @State private var now = Date()
    private let uiThrottle: TimeInterval = 5

    private enum SidebarPage: Hashable {
        case overview
        case provider(Provider)
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
            railTab(.overview, systemImage: "gauge.with.dots.needle.bottom.50percent", tint: .primary)
            ForEach(availableProviders, id: \.self) { provider in
                railTab(.provider(provider), systemImage: provider.iconName, tint: provider.accentColor)
            }

            Spacer()

            railAction("arrow.clockwise", help: "Refresh (⌘R)") {
                let tapped = Date()
                if let last = lastRefreshTap, tapped.timeIntervalSince(last) < uiThrottle { return }
                lastRefreshTap = tapped
                Task { await viewModel.refresh(force: true) }
            }
            railAction("gear", help: "Settings (⌘,)") {
                selectedTab = .settings
                openWindow(id: Constants.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            railAction("power", help: "Quit (⌘Q)") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
    }

    private func railTab(_ page: SidebarPage, systemImage: String, tint: Color) -> some View {
        let isSelected = selectedPage == page
        return Button {
            selectedPage = page
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? tint : .secondary)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? tint.opacity(0.15) : .clear)
                )
                .overlay(alignment: .leading) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(tint)
                            .frame(width: 3, height: 18)
                            .offset(x: -8)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func railAction(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            if updaterController.updateAvailable {
                updateBanner.padding([.horizontal, .top], 16)
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
            ProviderDetailView(
                provider: provider,
                planName: viewModel.usageSnapshot(for: provider)?.planName,
                windows: viewModel.usageSnapshot(for: provider)?.windows ?? [],
                detail: viewModel.providerDetails[provider],
                now: now,
                isServiceDown: viewModel.isServiceDown(provider),
                rateLimitResetCredits: viewModel.usageSnapshot(for: provider)?.rateLimitResetCredits
            )
        }
    }

    @ViewBuilder
    private var overviewPage: some View {
        let providers = availableProviders
        if providers.isEmpty {
            if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else {
                loadingSection
            }
        } else {
            VStack(spacing: 12) {
                // Surface a fetch error that's currently masked by cached cards, so
                // stale data is never shown as if it were live (e.g. a Claude token
                // that expired and couldn't be refreshed).
                if viewModel.isUsingCachedData, let error = viewModel.errorMessage {
                    staleDataBanner(error: error)
                }
                ForEach(providers, id: \.self) { provider in
                    overviewCard(provider)
                }
            }
        }
    }

    private func staleDataBanner(error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing cached usage")
                    .font(.footnote)
                    .fontWeight(.medium)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func overviewCard(_ provider: Provider) -> some View {
        ProviderCardView(
            provider: provider,
            planName: viewModel.usageSnapshot(for: provider)?.planName,
            windows: viewModel.usageSnapshot(for: provider)?.windows ?? [],
            extraUsage: provider == .claude && viewModel.showExtraUsageIndicators ? viewModel.snapshot?.extraUsage : nil,
            costLines: costLines(for: provider),
            now: now,
            showExtraUsage: provider == .claude && viewModel.showExtraUsageIndicators,
            compact: true,
            isServiceDown: viewModel.isServiceDown(provider),
            rateLimitResetCredits: viewModel.usageSnapshot(for: provider)?.rateLimitResetCredits
        )
    }

    // MARK: - Per-provider data

    private func costLines(for provider: Provider) -> [ProviderCostLine] {
        guard let detail = viewModel.providerDetails[provider] else { return [] }
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

    private var footer: some View {
        HStack {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("ClaudeMeter v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let snapshot = viewModel.snapshot {
                LastUpdatedLabel(
                    relativeText: DateFormatters.relativeDescription(from: snapshot.fetchedAt, to: now),
                    isCached: viewModel.isUsingCachedData,
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
}

#Preview {
    MenuBarView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
}
#endif
