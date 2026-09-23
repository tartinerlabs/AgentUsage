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
        // `min`/`max` pass NaN straight through, so reject non-finite values first.
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
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

    /// Drawn with shapes rather than a `GeometryReader`: widget layout on iOS 27
    /// traps in `GeometryReaderLayout.placeSubviews` when a measured width goes
    /// non-finite, while a shape only ever sees its final rect.
    public func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(track)

            UsageBarFill(fraction: configuration.value)
                .fill(tint)

            if showsTicks {
                UsageBarTicks()
                    .fill(Color.primary.opacity(0.15))
            }
        }
        .frame(height: 8)
    }
}

/// The leading `fraction` of the track, keeping the track's 4-point corners.
private struct UsageBarFill: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        guard rect.width.isFinite, clamped > 0 else { return Path() }
        var fill = rect
        fill.size.width = rect.width * clamped
        return RoundedRectangle(cornerRadius: 4).path(in: fill)
    }
}

/// One-point dividers at 25%, 50% and 75% of the track.
private struct UsageBarTicks: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite else { return Path() }
        var path = Path()
        for position in [0.25, 0.5, 0.75] {
            path.addRect(CGRect(x: rect.minX + rect.width * position, y: rect.minY, width: 1, height: rect.height))
        }
        return path
    }
}
