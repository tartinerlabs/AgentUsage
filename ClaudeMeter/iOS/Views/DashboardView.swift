//
//  DashboardView.swift
//  ClaudeMeter
//

#if os(iOS)
import ActivityKit
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
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
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
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
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

            UsageCardView(title: snapshot.opus.windowType.displayName, usage: snapshot.opus, now: now)
            if let sonnet = snapshot.sonnet {
                UsageCardView(title: sonnet.windowType.displayName, usage: sonnet, now: now)
            }
        }
    }

    // MARK: - States

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
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
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
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
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
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
