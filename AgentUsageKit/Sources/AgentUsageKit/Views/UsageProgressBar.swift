//
//  UsageProgressBar.swift
//  AgentUsageKit
//
//  Canonical linear usage indicator shared by app and extension surfaces.
//

import SwiftUI

/// The canonical AgentUsage progress track.
///
/// This preserves the iOS usage-row grammar: an 8-point Crail fill over a
/// secondary 20%-opacity track, with 25/50/75% dividers and 4-point corners.
public struct UsageProgressBar: View {
    /// Normalized progress in the closed range `0...1`.
    public let progress: Double

    public init(progress: Double) {
        self.progress = min(max(progress, 0), 1)
    }

    public init(usage: UsageWindow) {
        self.init(progress: usage.normalized)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(AgentUsageColors.usageProgress)
                    .frame(width: geometry.size.width * progress, height: 8)

                ForEach([0.25, 0.5, 0.75], id: \.self) { position in
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 1, height: 8)
                        .offset(x: geometry.size.width * position)
                }
            }
        }
        .frame(height: 8)
    }
}
