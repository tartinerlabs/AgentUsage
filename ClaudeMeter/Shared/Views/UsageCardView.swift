//
//  UsageCardView.swift
//  ClaudeMeter
//

import SwiftUI
import ClaudeMeterKit

/// Card-based usage display with progress ring
/// Used on iOS dashboard and can be used in widgets
struct UsageCardView: View {
    let title: String
    let usage: UsageWindow
    var now: Date = Date()
    var showExtraUsage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Label(usage.status.label, systemImage: usage.status.icon)
                    .font(.caption)
                    .foregroundStyle(usage.status.color)
            }

            HStack(spacing: 20) {
                progressRing
                    .accessibilityHidden(true) // Ring is decorative; info is in text

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(usage.percentUsed)%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(usage.status.color)
                    if showExtraUsage, usage.isUsingExtraUsage {
                        Text("+\(usage.extraUsagePercent)% extra")
                            .font(.caption)
                            .foregroundStyle(Constants.extraUsageAccent)
                    }
                    Text("Resets in \(usage.timeUntilReset(from: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Resets \(usage.timeUntilReset(from: now))")
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: usage.normalized)
                .stroke(
                    usage.status.color,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: usage.normalized)
        }
        .frame(width: 60, height: 60)
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
        utilization: 45,
        resetsAt: Date().addingTimeInterval(3600),
        windowType: .session
    )
    let opusUsage = UsageWindow(
        utilization: 78,
        resetsAt: Date().addingTimeInterval(86400 * 3),
        windowType: .opus
    )

    return VStack(spacing: 16) {
        UsageCardView(
            title: sessionUsage.windowType.displayName,
            usage: sessionUsage
        )
        UsageCardView(
            title: opusUsage.windowType.displayName,
            usage: opusUsage
        )
    }
    .padding()
}
