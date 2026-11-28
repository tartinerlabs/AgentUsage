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
                if showStatusDot, !hasRolledOver {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                }
                Spacer()
                Text(resetDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Progress bar — empty once the window has rolled over, since the
            // cached percentage belongs to the previous period.
            Group {
                if hasRolledOver {
                    UsageProgressBar(progress: 0)
                } else {
                    UsageProgressBar(usage: usage, now: now)
                }
            }
            .accessibilityHidden(true) // Progress bar is decorative; info is in text

            // Stats row
            HStack {
                HStack(spacing: 4) {
                    Text(usedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if showExtraUsage, !hasRolledOver, usage.isUsingExtraUsage {
                        Text("+\(usage.extraUsagePercent)% extra")
                            .font(.footnote)
                            .foregroundStyle(Constants.extraUsageAccent)
                    }
                }
                Spacer()
                if usage.lockedReason != nil {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !hasRolledOver {
                    Label(status.label, systemImage: status.icon)
                        .font(.footnote)
                        .foregroundStyle(status.color)
                }
            }
        }
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(resetDescription)
    }

    // MARK: - Accessibility Helpers

    private var accessibilityLabel: String {
        "\(title) usage"
    }

    /// The window reset after the shown data was fetched; its percentage is stale.
    private var hasRolledOver: Bool {
        usage.hasRolledOver(from: now)
    }

    private var resetDescription: String {
        hasRolledOver ? "Reset" : usage.resetDescription(from: now)
    }

    /// "12% used", or "$2.47 of $250.00 used" for a dollar-denominated window.
    private var usedDescription: String {
        if hasRolledOver { return "Waiting for update" }
        guard let budget = usage.budget else { return "\(usage.percentUsed)% used" }
        return "\(budget.formattedUsed) of \(budget.formattedLimit) used"
    }

    private var accessibilityValue: String {
        if hasRolledOver { return usedDescription }
        var parts = [usage.budget == nil ? "\(usage.percentUsed) percent used" : usedDescription]
        if usage.lockedReason != nil {
            parts.append("locked")
        }
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
