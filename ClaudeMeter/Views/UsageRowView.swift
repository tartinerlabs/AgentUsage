//
//  UsageRowView.swift
//  ClaudeMeter
//

import SwiftUI
import ClaudeMeterKit

struct UsageRowView: View {
    let title: String
    let usage: UsageWindow
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                Text("Resets in \(usage.timeUntilReset(from: now))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Constants.brandPrimary)
                        .frame(width: geometry.size.width * usage.normalized, height: 8)

                    // Dividers at 25%, 50%, 75%
                    ForEach([0.25, 0.5, 0.75], id: \.self) { position in
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1, height: 8)
                            .offset(x: geometry.size.width * position)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true) // Progress bar is decorative; info is in text

            // Stats row
            HStack {
                HStack(spacing: 4) {
                    Text("\(usage.percentUsed)% used")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if usage.isUsingExtraUsage {
                        Text("+\(usage.extraUsagePercent)% extra")
                            .font(.footnote)
                            .foregroundStyle(.purple)
                    }
                }
                Spacer()
                Label(usage.status.label, systemImage: usage.status.icon)
                    .font(.footnote)
                    .foregroundStyle(usage.status.color)
            }
        }
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Resets \(usage.timeUntilReset(from: now))")
    }

    // MARK: - Accessibility Helpers

    private var accessibilityLabel: String {
        "\(title) usage"
    }

    private var accessibilityValue: String {
        "\(usage.percentUsed) percent used, \(usage.status.label)"
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

    return VStack(spacing: 20) {
        UsageRowView(
            title: sessionUsage.windowType.displayName,
            usage: sessionUsage
        )
        UsageRowView(
            title: opusUsage.windowType.displayName,
            usage: opusUsage
        )
        UsageRowView(
            title: sonnetUsage.windowType.displayName,
            usage: sonnetUsage
        )
    }
    .padding()
    .frame(width: 300)
}
