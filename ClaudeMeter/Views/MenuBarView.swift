//
//  MenuBarView.swift
//  ClaudeMeter
//

import SwiftUI
internal import Combine

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var lastRefreshTap: Date?
    @State private var now = Date()
    private let uiThrottle: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.vertical, 8)

            // Content
            if let snapshot = viewModel.snapshot {
                contentSection(snapshot: snapshot)
            } else if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else {
                loadingSection
            }

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionsSection
        }
        .padding(16)
        .frame(width: 300)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Claude")
                    .font(.headline)
                Text(viewModel.planType)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            if let snapshot = viewModel.snapshot {
                Text("Updated \(relativeDescription(from: snapshot.fetchedAt, to: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Content

    private func contentSection(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 16) {
            UsageRowView(title: "Session", usage: snapshot.session)
            UsageRowView(title: "Opus", usage: snapshot.opus)
            if let sonnet = snapshot.sonnet {
                UsageRowView(title: "Sonnet", usage: sonnet)
            }

            // Token usage and cost
            if let tokenSnapshot = viewModel.tokenSnapshot {
                tokenCostSection(tokenSnapshot: tokenSnapshot)
            } else {
                Text("Token data loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Token Usage")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(tokenSnapshot.today.formattedTokens, systemImage: "text.word.spacing")
                        Label(tokenSnapshot.today.formattedCost, systemImage: "dollarsign.circle")
                            .foregroundStyle(Constants.brandPrimary)
                    }
                    .font(.caption)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("30 Days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(tokenSnapshot.last30Days.formattedTokens, systemImage: "text.word.spacing")
                        Label(tokenSnapshot.last30Days.formattedCost, systemImage: "dollarsign.circle")
                            .foregroundStyle(Constants.brandPrimary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView()
            Text("Loading...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 20)
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

            Spacer()

            SettingsLink {
                Label("Settings", systemImage: "gear")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
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
    MenuBarView()
        .environment(UsageViewModel())
}

