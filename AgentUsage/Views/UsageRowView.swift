//
//  UsageRowView.swift
//  AgentUsage
//

import SwiftUI
import AgentUsageKit

struct UsageRowView: View {
    let title: String
    let usage: UsageWindow
    var now: Date = Date()
    var showExtraUsage: Bool = true
    /// Show a small colored status dot before the title.
    var showStatusDot: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                if showStatusDot {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                }
                Spacer()
                Text(usage.resetDescription(from: now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            UsageProgressBar(usage: usage, now: now)
                .accessibilityHidden(true) // Progress bar is decorative; info is in text

            // Stats row
            HStack {
                HStack(spacing: 4) {
                    Text("\(usage.percentUsed)% used")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if showExtraUsage, usage.isUsingExtraUsage {
                        Text("+\(usage.extraUsagePercent)% extra")
                            .font(.footnote)
                            .foregroundStyle(Constants.extraUsageAccent)
                    }
                }
                Spacer()
                Label(status.label, systemImage: status.icon)
                    .font(.footnote)
                    .foregroundStyle(status.color)
            }
        }
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    // MARK: - Accessibility Helpers

    private var accessibilityLabel: String {
        "\(title) usage"
    }

    private var accessibilityValue: String {
        var parts = ["\(usage.percentUsed) percent used"]
        if showExtraUsage, usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        parts.append(status.label)
        return parts.joined(separator: ", ")
    }

    private var status: UsageStatus {
        usage.status(from: now)
    }
}

#Preview {
    let sessionUsage = UsageWindow(
        utilization: 25,
        resetsAt: Date().addingTimeInterval(3600),
        windowType: .session
    )
    let opusUsage = UsageWindow(
        utilization: 8,
        resetsAt: Date().addingTimeInterval(86400 * 3),
        windowType: .opus
    )
    let sonnetUsage = UsageWindow(
        utilization: 3,
        resetsAt: Date().addingTimeInterval(86400 * 3),
        windowType: .sonnet
    )
    let warningUsage = UsageWindow(
        utilization: 80,
        resetsAt: Date().addingTimeInterval(3600 * 4),
        windowType: .session
    )
    let criticalUsage = UsageWindow(
        utilization: 94,
        resetsAt: Date().addingTimeInterval(86400 * 2),
        windowType: .opus
    )

    return VStack(spacing: 20) {
        UsageRowView(
            title: sessionUsage.displayName,
            usage: sessionUsage
        )
        UsageRowView(
            title: opusUsage.displayName,
            usage: opusUsage
        )
        UsageRowView(
            title: sonnetUsage.displayName,
            usage: sonnetUsage
        )
        UsageRowView(
            title: warningUsage.displayName,
            usage: warningUsage
        )
        UsageRowView(
            title: criticalUsage.displayName,
            usage: criticalUsage
        )
    }
    .padding()
    .frame(width: 300)
}
