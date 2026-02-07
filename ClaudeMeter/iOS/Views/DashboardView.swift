//
//  DashboardView.swift
//  ClaudeMeter
//

#if os(iOS)
import ActivityKit
import ClaudeMeterKit
import Combine
import SwiftUI

/// Main iOS dashboard showing Claude usage
struct DashboardView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @StateObject private var liveActivityManager = LiveActivityManager.shared
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard

                if let snapshot = viewModel.snapshot {
                    // Offline indicator
                    if viewModel.isUsingCachedData {
                        offlineIndicator
                    }
                    // Extra usage banner
                    if snapshot.isExtraUsageActive {
                        extraUsageBanner
                    }
                    liveActivityCard(snapshot: snapshot)
                    usageCardsSection(snapshot: snapshot)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.isLoading {
                    loadingView
                } else {
                    emptyStateView
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .navigationTitle("ClaudeMeter")
        .task {
            await viewModel.initializeIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
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

    // MARK: - Live Activity Card

    @ViewBuilder
    private func liveActivityCard(snapshot: UsageSnapshot) -> some View {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(Constants.brandPrimary)
                    Text("Live Activity")
                        .font(.headline)
                    Spacer()
                    if liveActivityManager.isRunning {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if liveActivityManager.isRunning {
                    HStack {
                        Text("Tracking: \(liveActivityManager.selectedMetric.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") {
                            liveActivityManager.stop()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Stop live activity")
                        .accessibilityHint("Stops tracking usage in Dynamic Island")
                    }
                } else {
                    Text("Show usage in Dynamic Island")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([MetricType.session, .opus, .sonnet], id: \.self) { metric in
                            Button {
                                liveActivityManager.start(snapshot: snapshot, metric: metric)
                            } label: {
                                Text(metric.displayName)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Constants.brandPrimary)
                            .accessibilityLabel("Start \(metric.displayName) live activity")
                            .accessibilityHint("Shows \(metric.displayName) usage in Dynamic Island")
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live Activity controls")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Claude")
                    .font(.headline)
                Text(viewModel.planType)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Constants.brandPrimary.opacity(0.2))
                    .foregroundStyle(Constants.brandPrimary)
                    .clipShape(Capsule())
                if viewModel.snapshot?.hasExtraUsageEnabled == true {
                    Label("Extra Usage", systemImage: "plus.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Constants.extraUsageAccent)
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .accessibilityLabel("Loading")
                }
            }
            if let snapshot = viewModel.snapshot {
                Text("Updated \(snapshot.lastUpdatedDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude \(viewModel.planType) plan")
        .accessibilityValue(viewModel.snapshot.map { "Updated \($0.lastUpdatedDescription)" } ?? "")
    }

    // MARK: - Usage Cards

    @ViewBuilder
    private func usageCardsSection(snapshot: UsageSnapshot) -> some View {
        UsageCardView(title: snapshot.session.windowType.displayName, usage: snapshot.session, now: now)

        // Weekly limits group
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)

            UsageCardView(title: snapshot.opus.windowType.displayName, usage: snapshot.opus, now: now)
            if let sonnet = snapshot.sonnet {
                UsageCardView(title: sonnet.windowType.displayName, usage: sonnet, now: now)
            }
        }

        // Extra usage cost card
        if let extraUsage = snapshot.extraUsage {
            extraUsageCostCard(extraUsage)
        }
    }

    // MARK: - Extra Usage Cost Card

    private func extraUsageCostCard(_ extraUsage: ExtraUsageCost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Extra Usage")
                    .font(.headline)
                Spacer()
                Text("\(Int(min(100, max(0, extraUsage.percentUsed))))%")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Constants.extraUsageAccent)
            }

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

            HStack {
                Text("Monthly: \(extraUsage.formattedUsed) / \(extraUsage.formattedLimit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Extra usage spending")
        .accessibilityValue("\(extraUsage.formattedUsed) of \(extraUsage.formattedLimit) monthly limit")
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Constants.extraUsageAccent.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Extra usage active, API rates apply")
    }

    // MARK: - States

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
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
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
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading usage data")
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Data")
                .font(.headline)
            Text("Pull down to refresh")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data available")
        .accessibilityHint("Pull down to refresh")
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
