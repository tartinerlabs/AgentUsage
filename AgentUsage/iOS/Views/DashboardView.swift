//
//  DashboardView.swift
//  AgentUsage
//

#if os(iOS)
import AgentUsageKit
import Combine
import SwiftUI
import UIKit

/// Main iOS dashboard showing every available provider in one linear card stack.
struct DashboardView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isOffline || viewModel.isUsingCachedData {
                    offlineIndicator
                }

                let providerSnapshots = viewModel.availableProviderSnapshots
                if providerSnapshots.isEmpty {
                    dashboardState
                } else {
                    providerCards(providerSnapshots)
                }

                LiveActivityControlCard(
                    manager: viewModel.liveActivityManager,
                    snapshots: providerSnapshots,
                    now: now
                )

                if !viewModel.providersWithEffortUsage.isEmpty {
                    effortLevelsCard
                }
            }
            .frame(maxWidth: 760)
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .navigationTitle(Constants.appDisplayName)
        .task {
            await viewModel.initializeIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Effort Levels

    private var effortLevelsCard: some View {
        let providers = selectedEffortProviders

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Constants.brandPrimary)
                    .accessibilityHidden(true)
                Text("Effort Levels")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Picker(
                    "Effort period",
                    selection: Binding(
                        get: { viewModel.selectedTokenPeriod },
                        set: { viewModel.selectedTokenPeriod = $0 }
                    )
                ) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Effort period")
            }

            Divider()

            if providers.isEmpty {
                Text("No sessions in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(providers) { provider in
                    if provider != providers.first {
                        Divider()
                    }
                    if let summary = viewModel.effortSummary(
                        for: provider,
                        period: viewModel.selectedTokenPeriod.effortPeriod
                    ) {
                        EffortLevelsView(provider: provider, summary: summary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .contain)
    }

    private var selectedEffortProviders: [Provider] {
        viewModel.providersWithEffortUsage.filter { provider in
            guard let summary = viewModel.effortSummary(
                for: provider,
                period: viewModel.selectedTokenPeriod.effortPeriod
            ) else {
                return false
            }
            return summary.totalSessionCount > 0
        }
    }

    // MARK: - Provider Cards

    private func providerCards(_ snapshots: [ProviderUsageSnapshot]) -> some View {
        ForEach(snapshots) { snapshot in
            ProviderCardView(
                provider: snapshot.provider,
                planName: snapshot.planName,
                windows: snapshot.windows,
                extraUsage: snapshot.extraUsage,
                now: now,
                showExtraUsage: viewModel.showExtraUsageIndicators,
                isServiceDown: viewModel.isServiceDown(snapshot.provider),
                rateLimitResetCredits: snapshot.rateLimitResetCredits
            )
            .accessibilityLabel("\(snapshot.provider.displayName) usage")
        }
    }

    // MARK: - Offline Indicator

    private var offlineIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isOffline ? "wifi.slash" : "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isOffline ? "Offline Mode" : "Using Cached Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let lastUpdate = viewModel.timeSinceLastUpdate {
                    Text("Last updated \(lastUpdate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.isOffline ? "Offline mode" : "Using cached data")
        .accessibilityValue(viewModel.timeSinceLastUpdate.map { "Last updated \($0)" } ?? "")
    }

    // MARK: - Provider-neutral States

    @ViewBuilder
    private var dashboardState: some View {
        if viewModel.isNoUsageData {
            noUsageDataView
        } else if viewModel.isLoading || viewModel.isRefreshingContinuitySync {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            waitingView
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Unable to Load Usage")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await viewModel.refresh(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Constants.brandPrimary)
            .accessibilityHint("Attempts to reload usage data")
        }
        .stateCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error loading usage")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading usage data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading usage data")
    }

    private var noUsageDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No usage data")
                .font(.headline)
            Text("Usage limits will appear when a connected provider reports a new window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No usage data yet")
        .accessibilityHint("Usage limits will appear when a connected provider reports a new window")
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.largeTitle)
                .foregroundStyle(Constants.brandPrimary)
                .accessibilityHidden(true)
            Text("Waiting for usage")
                .font(.headline)
            Text("Open Agent Usage on your Mac to share the latest provider snapshots through iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Check Again") {
                    Task { await viewModel.refreshContinuitySync() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Constants.brandPrimary)

                Button("Setup Guide") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for usage from your Mac")
        .accessibilityHint("Open the setup guide or check for updates again")
    }
}

private extension View {
    func stateCard() -> some View {
        padding(40)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environment(UsageViewModel(
                credentialProvider: iOSCredentialService()
            ))
    }
}
#endif
