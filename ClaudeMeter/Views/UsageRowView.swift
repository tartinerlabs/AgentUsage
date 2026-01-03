//
//  UsageRowView.swift
//  ClaudeMeter
//

import SwiftUI

struct UsageRowView: View {
    let title: String
    let usage: UsageWindow
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Resets in \(usage.timeUntilReset(from: now))")
                    .font(.caption)
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

            // Stats row
            HStack {
                Text("\(usage.percentUsed)% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(usage.status.label, systemImage: usage.status.icon)
                    .font(.caption)
                    .foregroundStyle(usage.status.color)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageRowView(
            title: "Session",
            usage: UsageWindow(
                utilization: 25,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            )
        )
        UsageRowView(
            title: "Opus",
            usage: UsageWindow(
                utilization: 8,
                resetsAt: Date().addingTimeInterval(86400 * 3),
                windowType: .opus
            )
        )
        UsageRowView(
            title: "Sonnet",
            usage: UsageWindow(
                utilization: 3,
                resetsAt: Date().addingTimeInterval(86400 * 3),
                windowType: .sonnet
            )
        )
    }
    .padding()
    .frame(width: 300)
}
