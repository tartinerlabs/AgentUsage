//
//  DashboardTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI
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

                // Content
                if let snapshot = viewModel.snapshot {
                    usageSection(snapshot: snapshot)

                    if let tokenSnapshot = viewModel.tokenSnapshot {
                        tokenCostSection(tokenSnapshot: tokenSnapshot)
                    }
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
            UsageRowView(title: "Session", usage: snapshot.session, now: now)
            UsageRowView(title: "Opus", usage: snapshot.opus, now: now)
            if let sonnet = snapshot.sonnet {
                UsageRowView(title: "Sonnet", usage: sonnet, now: now)
            }
        }
    }

    // MARK: - Token Cost Section

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Token Usage & Cost")
                .font(.headline)

            HStack(spacing: 16) {
                // Today's usage
                tokenCard(
                    title: "Today",
                    cost: tokenSnapshot.today.formattedCost,
                    tokens: tokenSnapshot.today.formattedTokens
                )

                // 30-day usage
                tokenCard(
                    title: "30 Days",
                    cost: tokenSnapshot.last30Days.formattedCost,
                    tokens: tokenSnapshot.last30Days.formattedTokens
                )
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
