//
//  ProviderCardView.swift
//  AgentUsage
//
//  Reusable per-provider usage card.
//  Shared by the menu-bar popover, dashboards, and provider destinations.
//

import SwiftUI
import AgentUsageKit

/// How much of a provider's data a card should show.
enum ProviderCardDensity {
    /// Overview stack: windows, credits, extra usage, Today + 30 Days.
    case summary
    /// Destination: summary plus links, yesterday, trend, effort, models.
    case detail
}

/// A single cost row in a provider card (e.g. "Today", "30 Days").
struct ProviderCostLine: Identifiable {
    let label: String
    let cost: String
    let tokens: String
    var id: String { label }
}

/// Renders one provider's usage as a card. Sections appear only when data or a
/// capability is present. Attribution is name + glyph; chrome is always Crail.
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
    var density: ProviderCardDensity = .summary
    var detail: ProviderDetail? = nil
    var effortSummaries: [EffortPeriodSummary] = []
    var effortPeriod: EffortPeriod = .last30Days
    /// Max models to list in the breakdown.
    var maxModels: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            header

            if density == .detail, isServiceDown {
                serviceDownBanner
            }

            if density == .detail, !provider.links.isEmpty {
                linkButtons
            }

            if !windows.isEmpty {
                VStack(spacing: compact ? 10 : 14) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        UsageRowView(
                            title: window.displayName,
                            usage: window,
                            now: now,
                            showExtraUsage: showExtraUsage,
                            showStatusDot: density == .detail
                        )
                    }
                }
            }

            if let credits = rateLimitResetCredits {
                resetCreditsRow(credits)
            }

            if showExtraUsage, let extraUsage {
                ExtraUsageBarView(extraUsage: extraUsage)
            }

            if let detail {
                if !resolvedCostLines.isEmpty {
                    costSection
                } else if density == .detail, provider.supports(.tokenCost), !detail.hasTokenUsage {
                    Text("Local token usage is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if density == .detail {
                    if detail.dailyCosts.contains(where: { $0 > 0 }) {
                        trendSection(detail)
                    }
                    if let effortSummary = resolvedEffortSummary {
                        effortSection(effortSummary)
                    }
                    if detail.hasTokenUsage, !detail.modelShares.isEmpty {
                        modelsSection(detail)
                    }
                }
            } else if !resolvedCostLines.isEmpty {
                costSection
            } else if density == .detail, let effortSummary = resolvedEffortSummary {
                effortSection(effortSummary)
            }
        }
        .providerCardContainer(padding: compact ? 12 : 16)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .foregroundStyle(AgentUsageColors.usageProgress)
            Text(provider.displayName)
                .font(compact ? .headline : .title3)
                .fontWeight(.bold)
            if let planName, !planName.isEmpty {
                Text(planName.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(AgentUsageColors.usageProgress)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AgentUsageColors.usageProgress.opacity(0.12))
                    )
            }
            Spacer()
            if density == .summary, isServiceDown {
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
            ForEach(provider.links, id: \.label) { link in
                if let url = link.url {
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
        HStack(spacing: 6) {
            Text("Rate Limit Resets")
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if credits.hasImminentExpiry(now: now) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.orange)
                    .help(credits.tooltipText(now: now) ?? "")
            }
            Text("\(credits.availableCount) available")
                .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AgentUsageColors.usageProgress)
                .help(credits.tooltipText(now: now) ?? "")
        }
        .help(credits.tooltipText(now: now) ?? "")
    }

    // MARK: - Cost

    private var resolvedCostLines: [ProviderCostLine] {
        if !costLines.isEmpty { return costLines }
        guard let detail, detail.hasTokenUsage else { return [] }
        switch density {
        case .summary:
            return [
                ProviderCostLine(
                    label: "Today",
                    cost: detail.today.formattedCost,
                    tokens: detail.today.formattedTokens
                ),
                ProviderCostLine(
                    label: "30 Days",
                    cost: detail.last30Days.formattedCost,
                    tokens: detail.last30Days.formattedTokens
                ),
            ]
        case .detail:
            return [
                ProviderCostLine(
                    label: "Today",
                    cost: detail.today.formattedCost,
                    tokens: detail.today.formattedTokens
                ),
                ProviderCostLine(
                    label: "Yesterday",
                    cost: detail.yesterday.formattedCost,
                    tokens: detail.yesterday.formattedTokens
                ),
                ProviderCostLine(
                    label: "Last 30 Days",
                    cost: detail.last30Days.formattedCost,
                    tokens: detail.last30Days.formattedTokens
                ),
            ]
        }
    }

    private var costSection: some View {
        VStack(spacing: 8) {
            ForEach(resolvedCostLines) { line in
                ProviderCostRow(
                    label: line.label,
                    cost: line.cost,
                    tokens: line.tokens,
                    compact: compact
                )
            }
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
                    color: AgentUsageColors.usageProgress,
                    height: 36,
                    width: geo.size.width,
                    style: .bars,
                    autoScale: true
                )
            }
            .frame(height: 36)
        }
    }

    private var resolvedEffortSummary: EffortPeriodSummary? {
        if let summary = detail?.effortSummaries.first(where: { $0.period == effortPeriod }) {
            return summary
        }
        return effortSummaries.first(where: { $0.period == effortPeriod })
    }

    // MARK: - Effort Levels

    private func effortSection(_ summary: EffortPeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effort Levels \u{00b7} \(summary.period.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .accessibilityAddTraits(.isHeader)
            EffortLevelsView(provider: provider, summary: summary, showsProviderHeader: false)
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
}

/// Canonical provider cost metric shared by summary and detail presentations.
struct ProviderCostRow: View {
    let label: String
    let cost: String
    let tokens: String
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                Text(tokens)
                    .font(.footnote)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            Text(cost)
                .font(.system(size: compact ? 16 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(AgentUsageColors.usageProgress)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) cost")
        .accessibilityValue("\(cost), \(tokens) tokens")
    }
}

/// Shared provider-card chrome used by the iOS dashboard and every adapted app
/// surface. Keeping the fill, border, radius, and padding together prevents a
/// provider card from changing visual language when its content gets richer.
struct ProviderCardContainerModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AgentUsageColors.usageProgress.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AgentUsageColors.usageProgress.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    func providerCardContainer(padding: CGFloat = 16) -> some View {
        modifier(ProviderCardContainerModifier(padding: padding))
    }
}

/// Provider-neutral on-demand spend meter used by cards and detail views.
struct ExtraUsageBarView: View {
    let extraUsage: ExtraUsageCost

    var body: some View {
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
}
