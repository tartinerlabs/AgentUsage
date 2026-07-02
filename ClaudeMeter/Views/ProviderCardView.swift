//
//  ProviderCardView.swift
//  ClaudeMeter
//
//  Reusable per-provider usage card (OpenUsage-style "weather station").
//  Shared by the menu-bar popover and the dashboard.
//

import SwiftUI
import ClaudeMeterKit

/// A single cost row in a provider card (e.g. "Today", "30 Days").
struct ProviderCostLine: Identifiable {
    let label: String
    let cost: String
    let tokens: String
    var id: String { label }
}

/// Renders one provider's usage as a card: header (icon + name + plan),
/// rate-limit window rows, optional extra-usage bar, and cost lines.
struct ProviderCardView: View {
    let provider: Provider
    var planName: String? = nil
    var windows: [UsageWindow] = []
    var extraUsage: ExtraUsageCost? = nil
    var costLines: [ProviderCostLine] = []
    var now: Date = Date()
    var showExtraUsage: Bool = true
    var compact: Bool = false
    var isServiceDown: Bool = false
    var rateLimitResetCredits: RateLimitResetCredits? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            header

            if !windows.isEmpty {
                VStack(spacing: compact ? 10 : 14) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        UsageRowView(
                            title: window.windowType.displayName,
                            usage: window,
                            now: now,
                            showExtraUsage: showExtraUsage
                        )
                    }
                }
            }

            if let credits = rateLimitResetCredits {
                HStack(spacing: 6) {
                    Text("Rate Limit Resets")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if credits.hasImminentExpiry(now: now) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    Text("\(credits.availableCount) available")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(provider.accentColor)
                }
                .help(credits.tooltipText(now: now) ?? "")
            }

            if showExtraUsage, let extraUsage {
                extraUsageBar(extraUsage)
            }

            if !costLines.isEmpty {
                costSection
            }
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(provider.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(provider.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .foregroundStyle(provider.accentColor)
            Text(provider.displayName)
                .font(compact ? .headline : .title3)
                .fontWeight(.bold)
            if let planName, !planName.isEmpty {
                Text(planName.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(provider.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(provider.accentColor.opacity(0.12))
                    )
            }
            Spacer()
            if isServiceDown {
                serviceDownBadge
            }
        }
    }

    private var serviceDownBadge: some View {
        Label("Service down", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red.opacity(0.12))
            )
            .help("This provider's service recently returned a server error. Showing cached data.")
    }

    private func extraUsageBar(_ extraUsage: ExtraUsageCost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Constants.extraUsageAccent)
                        .frame(width: geo.size.width * extraUsage.normalized, height: 8)
                }
            }
            .frame(height: 8)

            Text("Extra usage: \(extraUsage.formattedUsed) / \(extraUsage.formattedLimit)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var costSection: some View {
        VStack(spacing: 8) {
            ForEach(costLines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption2)
                        Text(line.tokens)
                            .font(.footnote)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    Text(line.cost)
                        .font(.system(size: compact ? 16 : 20, weight: .bold, design: .rounded))
                        .foregroundStyle(provider.accentColor)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
        }
    }
}
