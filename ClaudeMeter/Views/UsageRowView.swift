//
//  UsageRowView.swift
//  ClaudeMeter
//

import SwiftUI

struct UsageRowView: View {
    let title: String
    let usage: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Gauge(value: usage.normalized) {
                Text(title)
            } currentValueLabel: {
                Text("\(usage.percentUsed)%")
                    .foregroundStyle(usage.color)
            }
            .gaugeStyle(.linearCapacity)
            .tint(usage.color)

            Text("Resets in \(usage.timeUntilReset)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageRowView(
            title: "Session (5hr)",
            usage: UsageWindow(utilization: 45, resetsAt: Date().addingTimeInterval(3600))
        )
        UsageRowView(
            title: "Weekly",
            usage: UsageWindow(utilization: 75, resetsAt: Date().addingTimeInterval(86400))
        )
    }
    .padding()
    .frame(width: 280)
}
