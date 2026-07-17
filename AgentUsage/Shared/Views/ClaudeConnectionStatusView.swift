//
//  ClaudeConnectionStatusView.swift
//  AgentUsage
//
//  Consistent "connected to Claude" status row shared by macOS and iOS/iPadOS
//  settings so both platforms present connection health identically.
//

import SwiftUI

struct ClaudeConnectionStatusView: View {
    let status: ClaudeConnectionStatus
    /// Relative time since the last successful fetch, e.g. "2 minutes ago".
    var lastUpdatedText: String?

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.body)
                    .foregroundStyle(status.tint)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.title)
        .accessibilityValue(detail ?? "")
    }

    @ViewBuilder
    private var statusIcon: some View {
        if status.isInProgress {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
        }
    }

    /// Secondary line: last successful fetch, guidance, or the underlying error.
    private var detail: String? {
        switch status {
        case .connected, .cached, .offline, .serviceUnavailable:
            return lastUpdatedText.map { "Last updated \($0)" }
        case .noUsageData:
            return "No usage yet — your limits appear after your next Claude prompt."
        case .checking:
            return "Contacting Claude…"
        case .disconnected(let message):
            return message ?? "Add your Claude credentials to connect."
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ClaudeConnectionStatusView(status: .connected, lastUpdatedText: "2 minutes ago")
        ClaudeConnectionStatusView(status: .cached, lastUpdatedText: "1 hour ago")
        ClaudeConnectionStatusView(status: .offline, lastUpdatedText: "3 hours ago")
        ClaudeConnectionStatusView(status: .noUsageData)
        ClaudeConnectionStatusView(status: .serviceUnavailable, lastUpdatedText: "5 minutes ago")
        ClaudeConnectionStatusView(status: .checking)
        ClaudeConnectionStatusView(status: .disconnected(message: nil))
        ClaudeConnectionStatusView(status: .disconnected(message: "Invalid credentials."))
    }
    .padding()
}
