//
//  MenuBarView.swift
//  ClaudeMeter
//

import SwiftUI
internal import Combine

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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

            // Token usage and cost (shown when available, no loading indicator)
            if let tokenSnapshot = viewModel.tokenSnapshot {
                tokenCostSection(tokenSnapshot: tokenSnapshot)
            }
        }
    }

    private func tokenCostSection(tokenSnapshot: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Token Usage & Cost")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Today's usage - prominent display
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline) {
                    Text(tokenSnapshot.today.formattedCost)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.brandPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption)
                        Text(tokenSnapshot.today.formattedTokens)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Constants.brandPrimary.opacity(0.08))
            )

            // 30-day usage - prominent display
            VStack(alignment: .leading, spacing: 8) {
                Text("30 Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline) {
                    Text(tokenSnapshot.last30Days.formattedCost)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.brandPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption)
                        Text(tokenSnapshot.last30Days.formattedTokens)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Constants.brandPrimary.opacity(0.08))
            )
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

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            } label: {
                Label("About", systemImage: "info.circle")
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
        .environmentObject(UpdaterController())
}

