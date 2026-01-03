//
//  UsageCardView.swift
//  ClaudeMeter
//

import SwiftUI

/// Card-based usage display with progress ring
/// Used on iOS dashboard and can be used in widgets
struct UsageCardView: View {
    let title: String
    let usage: UsageWindow
    var now: Date = Date()

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

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(usage.percentUsed)%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(usage.status.color)
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
}

#Preview {
    VStack(spacing: 16) {
        UsageCardView(
            title: "Session",
            usage: UsageWindow(
                utilization: 45,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            )
        )
        UsageCardView(
            title: "Opus",
            usage: UsageWindow(
                utilization: 78,
                resetsAt: Date().addingTimeInterval(86400 * 3),
                windowType: .opus
            )
        )
    }
    .padding()
}
