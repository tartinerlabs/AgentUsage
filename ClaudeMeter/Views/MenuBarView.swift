//
//  MenuBarView.swift
//  ClaudeMeter
//

import SwiftUI

struct MenuBarView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // Content
            if let snapshot = viewModel.snapshot {
                UsageRowView(title: "Session (5hr)", usage: snapshot.session)
                UsageRowView(title: "Weekly", usage: snapshot.weekly)

                Divider()

                Text("Updated \(snapshot.lastUpdatedDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Error", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            HStack {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Spacer()

                SettingsLink {
                    Text("Settings")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    MenuBarView()
        .environment(UsageViewModel())
}
