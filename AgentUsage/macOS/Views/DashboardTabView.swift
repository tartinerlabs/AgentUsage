//
//  DashboardTabView.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI
import AgentUsageKit
internal import Combine

/// Dashboard view for the main window, displaying usage stats and token costs
struct DashboardTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @State private var now = Date()

    private let contentWidth: CGFloat = 760

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overviewHeader

                if updaterController.updateAvailable {
                    updateBanner
                }

                if viewModel.showExtraUsageIndicators, viewModel.snapshot?.isExtraUsageActive == true {
                    extraUsageBanner
                }

                providerSections

                // Gated on token state, not on the Claude API: this section is built from
                // local JSONL logs, so an API outage or a reset window must not hide it.
                if hasTokenUsageContent {
                    dashboardSection(
                        title: "Token Usage & Cost",
                        subtitle: "Local Claude token activity and estimated spend.",
                        systemImage: "square.stack.3d.up"
                    ) {
                        tokenUsageSectionWithStates
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh usage data")
            }
        }
        .task {
            await viewModel.initializeIfNeeded()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) {
            now = $0
        }
    }

    // MARK: - Header

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usage Overview")
                        .font(.title2.weight(.semibold))
                    Text("Live quota windows and local token cost, arranged by provider.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                statusBadge
            }

            HStack(spacing: 8) {
                if viewModel.isLoading || viewModel.isLoadingTokenUsage {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let snapshot = viewModel.snapshot {
                    LastUpdatedLabel(
                        relativeText: relativeDescription(from: snapshot.fetchedAt, to: now),
                        isCached: viewModel.isUsingCachedData,
                        isOffline: viewModel.isOffline,
                        font: .caption,
                        neutralStyle: AnyShapeStyle(.secondary)
                    )
                } else {
                    Text("Waiting for provider data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusBadge: some View {
        let status = viewModel.overallStatus
        return Label(status.label, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status.color.opacity(0.12))
            )
            .accessibilityLabel("Overall usage pressure: \(status.label)")
    }

    // MARK: - Provider Sections

    @ViewBuilder
    private var providerSections: some View {
        if let usage = viewModel.usageSnapshot(for: .claude) {
            dashboardSection(
                title: Provider.claude.displayName,
                subtitle: "Subscription windows and local cost detail.",
                systemImage: Provider.claude.iconName,
                tint: Provider.claude.accentColor
            ) {
                ProviderDetailView(
                    provider: .claude,
                    planName: usage.planName,
                    windows: usage.windows,
                    detail: viewModel.providerDetails[.claude],
                    now: now,
                    isServiceDown: viewModel.isServiceDown(.claude)
                )

                if viewModel.showExtraUsageIndicators, let extraUsage = usage.extraUsage {
                    Divider()
                    extraUsageCostSection(extraUsage)
                }
            }
        } else if viewModel.isNoUsageData {
            noUsageDataSection
        } else if let error = viewModel.errorMessage {
            errorSection(error: error)
        } else {
            loadingSection
        }

        if viewModel.hasProviderData(.codex) {
            let codex = viewModel.usageSnapshot(for: .codex)
            dashboardSection(
                title: Provider.codex.displayName,
                subtitle: "ChatGPT subscription windows and local cost detail.",
                systemImage: Provider.codex.iconName,
                tint: Provider.codex.accentColor
            ) {
                ProviderDetailView(
                    provider: .codex,
                    planName: codex?.planName,
                    windows: codex?.windows ?? [],
                    detail: viewModel.providerDetails[.codex],
                    now: now,
                    isServiceDown: viewModel.isServiceDown(.codex),
                    rateLimitResetCredits: codex?.rateLimitResetCredits
                )
            }
        }

        if viewModel.hasProviderData(.openCode) {
            let openCodeUsage = viewModel.usageSnapshot(for: .openCode)
            dashboardSection(
                title: Provider.openCode.displayName,
                subtitle: "Local OpenCode activity and optional quota data.",
                systemImage: Provider.openCode.iconName,
                tint: Provider.openCode.accentColor
            ) {
                ProviderDetailView(
                    provider: .openCode,
                    planName: openCodeUsage?.planName,
                    windows: openCodeUsage?.windows ?? [],
                    detail: viewModel.providerDetails[.openCode],
                    now: now,
                    isServiceDown: viewModel.isServiceDown(.openCode)
                )
            }
        }

        if viewModel.hasProviderData(.openCodeGo) {
            let openCodeGoUsage = viewModel.usageSnapshot(for: .openCodeGo)
            dashboardSection(
                title: Provider.openCodeGo.displayName,
                subtitle: "OpenCode Go quota windows and local cost detail.",
                systemImage: Provider.openCodeGo.iconName,
                tint: Provider.openCodeGo.accentColor
            ) {
                ProviderDetailView(
                    provider: .openCodeGo,
                    planName: openCodeGoUsage?.planName,
                    windows: openCodeGoUsage?.windows ?? [],
                    detail: viewModel.providerDetails[.openCodeGo],
                    now: now,
                    isServiceDown: viewModel.isServiceDown(.openCodeGo)
                )
            }
        }
    }

    private func dashboardSection<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = Constants.brandPrimary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
            }

            Divider()

            content()
        }
        .padding(18)
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

    // MARK: - Token Cost Section

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cost summary")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Period", selection: $viewModel.selectedTokenPeriod) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 112)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                tokenCard(
                    title: "Today",
                    cost: tokenSnapshot.today.formattedCost,
                    tokens: tokenSnapshot.today.formattedTokens
                )

                let summary = viewModel.selectedPeriodSummary
                let title = viewModel.selectedTokenPeriod.rawValue
                if let summary {
                    tokenCard(
                        title: title,
                        cost: summary.formattedCost,
                        tokens: summary.formattedTokens
                    )
                } else {
                    tokenCard(
                        title: title,
                        cost: tokenSnapshot.last30Days.formattedCost,
                        tokens: tokenSnapshot.last30Days.formattedTokens
                    )
                }
            }
        }
    }

    private func tokenCard(title: String, cost: String, tokens: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline) {
                Text(cost)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.brandPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()
            }

            Label(tokens, systemImage: "square.stack.3d.up")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.brandPrimary.opacity(0.08))
        )
    }

    // MARK: - Token Usage Section with States

    /// Whether `tokenUsageSectionWithStates` has anything to render, so the section
    /// header is not shown above empty content.
    private var hasTokenUsageContent: Bool {
        viewModel.tokenSnapshot != nil
            || viewModel.isLoadingTokenUsage
            || viewModel.tokenUsageError != nil
    }

    @ViewBuilder
    private var tokenUsageSectionWithStates: some View {
        if let tokenSnapshot = viewModel.tokenSnapshot {
            tokenCostSection(tokenSnapshot: tokenSnapshot)
                .task(id: viewModel.selectedTokenPeriod) {
                    await viewModel.refreshSelectedPeriodSummary()
                }
        } else if viewModel.isLoadingTokenUsage {
            tokenLoadingSection
        } else if let error = viewModel.tokenUsageError {
            tokenErrorSection(error: error)
        }
    }

    private var tokenLoadingSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            tokenLoadingCard(title: "Today")
            tokenLoadingCard(title: "30 Days")
        }
    }

    private func tokenLoadingCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .frame(height: 40)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.brandPrimary.opacity(0.08))
        )
    }

    private func tokenErrorSection(error: TokenUsageError) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unable to load token data")
                    .font(.subheadline.weight(.semibold))
                Text(error.errorDescription ?? "Unknown error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh(force: true) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoadingTokenUsage)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.subheadline.weight(.semibold))
                Text("Open the updater to review the latest \(Constants.appDisplayName) release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("View") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Extra Usage Cost Section

    private func extraUsageCostSection(_ extraUsage: ExtraUsageCost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extra usage")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Constants.extraUsageAccent)
                            .frame(width: geometry.size.width * extraUsage.normalized, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Monthly: \(extraUsage.formattedUsed) / \(extraUsage.formattedLimit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(min(100, max(0, extraUsage.percentUsed))))% used")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Extra Usage Banner

    private var extraUsageBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(Constants.extraUsageAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Extra usage active")
                    .font(.subheadline.weight(.semibold))
                Text("Plan limit exceeded. API rates apply while this window is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.extraUsageAccent.opacity(0.1))
        )
    }

    // MARK: - Error & Loading

    private var noUsageDataSection: some View {
        dashboardSection(
            title: "No usage data",
            subtitle: "Your usage limits will appear after your next Claude prompt.",
            systemImage: "chart.bar.xaxis"
        ) {
            Text("\(Constants.appDisplayName) has not received an active provider window yet.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func errorSection(error: String) -> some View {
        dashboardSection(
            title: "Unable to refresh usage",
            subtitle: "The latest provider request failed.",
            systemImage: "exclamationmark.triangle.fill",
            tint: .red
        ) {
            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingSection: some View {
        dashboardSection(
            title: "Loading usage data",
            subtitle: "Fetching provider windows and local token history.",
            systemImage: "arrow.clockwise"
        ) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking current usage")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private func relativeDescription(from past: Date, to current: Date) -> String {
        let delta = current.timeIntervalSince(past)
        if delta < 1.5 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: past, relativeTo: current)
    }
}

#Preview {
    DashboardTabView()
        .environment(UsageViewModel(credentialProvider: MacOSCredentialService()))
        .environmentObject(UpdaterController())
        .frame(width: 760, height: 640)
}
#endif
