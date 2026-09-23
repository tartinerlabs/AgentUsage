//
//  UsageProgressBar.swift
//  AgentUsageKit
//
//  Canonical linear usage indicator shared by app and extension surfaces.
//

import SwiftUI

/// The canonical AgentUsage progress track.
///
/// This preserves the iOS usage-row grammar: an 8-point fill over a secondary
/// 20%-opacity track, with 25/50/75% dividers and 4-point corners. A usage
/// window fills with its semantic status colour; a bare progress value uses
/// the neutral primary.
public struct UsageProgressBar: View {
    /// Normalized progress in the closed range `0...1`.
    public let progress: Double
    let tint: Color

    public init(progress: Double, tint: Color = AgentUsageColors.usageProgress) {
        self.progress = min(max(progress, 0), 1)
        self.tint = tint
    }

    /// Fills with the window's semantic status colour. Only use this where the
    /// matching status symbol is also shown — a status colour never travels alone.
    public init(usage: UsageWindow, now: Date) {
        self.init(progress: usage.normalized, tint: usage.status(from: now).color)
    }

    public var body: some View {
        Gauge(value: progress) {
            Text("Usage")
        }
        .gaugeStyle(UsageBarGaugeStyle(tint: tint, showsTicks: true))
    }
}

/// The 8-point, 4-point-radius bar shared by every linear meter in the app.
///
/// `Gauge` ignores `markedValueLabels` and `GaugeStyleConfiguration` does not
/// expose them, so the quarter dividers are drawn here rather than passed in.
public struct UsageBarGaugeStyle: GaugeStyle {
    let tint: Color
    let track: Color
    let showsTicks: Bool

    public init(
        tint: Color,
        track: Color = Color.secondary.opacity(0.2),
        showsTicks: Bool = false
    ) {
        self.tint = tint
        self.track = track
        self.showsTicks = showsTicks
    }

    public func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(track)

                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: geometry.size.width * configuration.value)

                if showsTicks {
                    ForEach([0.25, 0.5, 0.75], id: \.self) { position in
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1)
                            .offset(x: geometry.size.width * position)
                    }
                }
            }
        }
        .frame(height: 8)
    }
}
