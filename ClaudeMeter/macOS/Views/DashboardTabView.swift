//
//  DashboardTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI
import ClaudeMeterKit
internal import Combine

/// Dashboard view for the main window, displaying usage stats and token costs
struct DashboardTabView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Update banner (if available)
                if updaterController.updateAvailable {
                    updateBanner
                }

                // Header
                headerSection

                Divider()

                // Extra usage banner
                if viewModel.showExtraUsageIndicators, viewModel.snapshot?.isExtraUsageActive == true {
                    extraUsageBanner
                }

                // Content
                if let snapshot = viewModel.snapshot {
                    usageSection(snapshot: snapshot)

                    // Extra usage cost section
                    if viewModel.showExtraUsageIndicators, let extraUsage = snapshot.extraUsage {
                        extraUsageCostSection(extraUsage)
                    }

                    // Token usage section with error/loading states
                    tokenUsageSectionWithStates
                } else if let error = viewModel.errorMessage {
                    errorSection(error: error)
                } else {
                    loadingSection
                }
            }
            .padding(24)
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
            }
        }
        .task {
            await viewModel.initializeIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) {
            now = $0
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Claude")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(viewModel.planType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if viewModel.showExtraUsageIndicators, viewModel.snapshot?.hasExtraUsageEnabled == true {
                    Label("Extra Usage", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Constants.extraUsageAccent)
                }
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            if let snapshot = viewModel.snapshot {
                Text("Updated \(relativeDescription(from: snapshot.fetchedAt, to: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Usage Section

    private func usageSection(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 16) {
            UsageRowView(title: snapshot.session.windowType.displayName, usage: snapshot.session, now: now, showExtraUsage: viewModel.showExtraUsageIndicators)

            // Weekly limits group
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                UsageRowView(title: snapshot.opus.windowType.displayName, usage: snapshot.opus, now: now, showExtraUsage: viewModel.showExtraUsageIndicators)
                if let sonnet = snapshot.sonnet {
                    UsageRowView(title: sonnet.windowType.displayName, usage: sonnet, now: now, showExtraUsage: viewModel.showExtraUsageIndicators)
                }
            }
        }
    }

    // MARK: - Token Cost Section

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Token Usage & Cost")
                    .font(.headline)

                Spacer()

                Picker("Period", selection: $viewModel.selectedTokenPeriod) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)

                if viewModel.isFetchingPeriodSummaries {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            HStack(spacing: 16) {
                // Today's usage (always shown)
                tokenCard(
                    title: "Today",
                    cost: tokenSnapshot.today.formattedCost,
                    tokens: tokenSnapshot.today.formattedTokens
                )

                // Selected period usage (prefer cached summary)
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
                        title: "30 Days",
                        cost: tokenSnapshot.last30Days.formattedCost,
                        tokens: tokenSnapshot.last30Days.formattedTokens
                    )
                }
            }
        }
    }

    private func tokenCard(title: String, cost: String, tokens: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline) {
                Text(cost)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.brandPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.caption)
                    Text(tokens)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.brandPrimary.opacity(0.08))
        )
    }

    // MARK: - Token Usage Section with States

    @ViewBuilder
    private var tokenUsageSectionWithStates: some View {
        if let tokenSnapshot = viewModel.tokenSnapshot {
            tokenCostSection(tokenSnapshot: tokenSnapshot)
        } else if viewModel.isLoadingTokenUsage {
            tokenLoadingSection
        } else if let error = viewModel.tokenUsageError {
            tokenErrorSection(error: error)
        }
        // If no snapshot, not loading, and no error - silently hide (first load case)
    }

    private var tokenLoadingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Token Usage & Cost")
                    .font(.headline)
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }

            HStack(spacing: 16) {
                tokenLoadingCard(title: "Today")
                tokenLoadingCard(title: "30 Days")
            }
        }
    }

    private func tokenLoadingCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .frame(height: 32)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.brandPrimary.opacity(0.08))
        )
    }

    private func tokenErrorSection(error: TokenUsageError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Token Usage & Cost")
                    .font(.headline)
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

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Unable to load token data")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)
            Text("Update Available")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
            Button("View") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange)
        )
    }

    // MARK: - Extra Usage Cost Section

    private func extraUsageCostSection(_ extraUsage: ExtraUsageCost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extra Usage")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // Progress bar
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

                // Spend line
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
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(Constants.extraUsageAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Extra Usage Active")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("You've exceeded your plan limit. API rates apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Constants.extraUsageAccent.opacity(0.1)))
    }

    // MARK: - Error & Loading

    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)
            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
        .frame(width: 500, height: 400)
}
#endif

