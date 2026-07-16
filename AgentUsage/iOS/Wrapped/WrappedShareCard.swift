//
//  WrappedShareCard.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI

/// A branded, fixed-layout card summarizing the year, rendered to an image for
/// social sharing via `ImageRenderer`.
///
/// Uses solid brand fills only — no gradients or shadows, per DESIGN.md — so it
/// renders deterministically offscreen and reads the same in every appearance.
/// The colour scheme is pinned to light because the brand ground (Pampas) is a
/// fixed sRGB value that does not adapt to dark mode.
struct WrappedShareCard: View {
    let summary: WrappedSummary

    /// Natural design size in points. `ImageRenderer.scale` controls output pixels
    /// (scale 3 → 1080×1350, a 4:5 social ratio).
    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Wrapped")
                    .font(.system(size: 15, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Constants.brandPrimary)
                Text(String(summary.year))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 16) {
                stat(WrappedFormat.tokens(summary.totalTokens), "tokens")
                stat(WrappedFormat.cost(summary.totalCostUSD), "spent")
                if let top = summary.topModel {
                    stat(top.modelName, "top model · \(WrappedFormat.percent(top.fraction))")
                }
                stat("\(summary.activeDays)", "active days")
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "gift")
                Text(Constants.appDisplayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Constants.brandBackground)
        .environment(\.colorScheme, .light)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.brandPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WrappedShareCard(summary: .mock)
}
#endif
