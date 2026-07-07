//
//  ProviderDetailView.swift
//  ClaudeMeter
//
//  OpenUsage-style per-provider detail page: header + links, rate-limit
//  windows, Today/Yesterday/30-day cost, usage-trend sparkline, per-model.
//

#if os(macOS)
import SwiftUI
import ClaudeMeterKit

struct ProviderDetailView: View {
    let provider: Provider
    var planName: String? = nil
    var windows: [UsageWindow] = []
    var detail: ProviderDetail? = nil
    var now: Date = Date()
    /// Max models to list in the breakdown.
    var maxModels: Int = 6
    var isServiceDown: Bool = false
    /// On-demand rate-limit reset credits (Codex only).
    var rateLimitResetCredits: RateLimitResetCredits? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isServiceDown {
                serviceDownBanner
            }

            if !links.isEmpty {
                linkButtons
            }

            if !windows.isEmpty {
                VStack(spacing: 14) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        UsageRowView(title: window.windowType.displayName, usage: window, now: now, showStatusDot: true)
                    }
                }
            }

            if let credits = rateLimitResetCredits {
                resetCreditsRow(credits)
            }

            if let detail {
                costSection(detail)
                if detail.dailyCosts.contains(where: { $0 > 0 }) {
                    trendSection(detail)
                }
                if !detail.modelShares.isEmpty {
                    modelsSection(detail)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .foregroundStyle(provider.accentColor)
            Text(provider.displayName)
                .font(.title3)
                .fontWeight(.bold)
            if let planName, !planName.isEmpty {
                Text(planName.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(provider.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(provider.accentColor.opacity(0.12)))
            }
            Spacer()
        }
    }

    private var serviceDownBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(provider.displayName) is unavailable")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("The service returned a server error. Showing cached data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
    }

    private var linkButtons: some View {
        HStack(spacing: 8) {
            ForEach(links, id: \.label) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        HStack(spacing: 3) {
                            Text(link.label)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    // MARK: - Reset Credits

    private func resetCreditsRow(_ credits: RateLimitResetCredits) -> some View {
        HStack(spacing: 8) {
            Text("Rate Limit Resets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if credits.hasImminentExpiry(now: now) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(credits.tooltipText(now: now) ?? "")
            }
            Text("\(credits.availableCount) available")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(provider.accentColor)
                .help(credits.tooltipText(now: now) ?? "")
        }
    }

    // MARK: - Cost

    private func costSection(_ detail: ProviderDetail) -> some View {
        VStack(spacing: 8) {
            costRow("Today", detail.today)
            costRow("Yesterday", detail.yesterday)
            costRow("Last 30 Days", detail.last30Days)
        }
    }

    private func costRow(_ label: String, _ summary: TokenUsageSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(summary.formattedCost)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(provider.accentColor)
            Text("· \(summary.formattedTokens) tokens")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Trend

    private func trendSection(_ detail: ProviderDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage Trend")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            GeometryReader { geo in
                SparklineView(
                    values: detail.dailyCosts,
                    color: provider.accentColor,
                    height: 36,
                    width: geo.size.width,
                    style: .bars,
                    autoScale: true
                )
            }
            .frame(height: 36)
        }
    }

    // MARK: - Models

    private func modelsSection(_ detail: ProviderDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(detail.modelShares.prefix(maxModels), id: \.model) { share in
                HStack {
                    Text(share.model)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(percentLabel(share.percent))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func percentLabel(_ percent: Double) -> String {
        percent < 0.1 ? "<0.1%" : String(format: "%.1f%%", percent)
    }

    // MARK: - Links

    private var links: [(label: String, url: String)] {
        switch provider {
        case .claude:
            return [("Status", Constants.anthropicStatusURL), ("Usage", Constants.anthropicConsoleURL)]
        case .codex:
            return [("Status", Constants.openaiStatusURL), ("Usage", Constants.openaiPlatformURL)]
        case .openCode:
            return []
        case .cursor:
            return [("Status", Constants.cursorStatusURL), ("Dashboard", Constants.cursorDashboardURL)]
        }
    }
}
#endif
