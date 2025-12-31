//
//  MenuBarView.swift
//  ClaudeMeter
//

import SwiftUI

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel

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
                Text("Updated \(snapshot.lastUpdatedDescription)")
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
                Task { await viewModel.refresh() }
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
}

#Preview {
    MenuBarView()
        .environment(UsageViewModel())
}
