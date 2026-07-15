//
//  ClaudeWrappedView.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI
import Charts
import UIKit

/// "Claude Wrapped" — a year-in-review of Claude Code usage.
///
/// Currently driven by ``WrappedSummary/mock``; the CloudKit sync core that will
/// supply real yearly data is tracked in GitHub #8. Visuals follow DESIGN.md:
/// `.regularMaterial` cards, Crail (`brandPrimary`) accents, rounded-bold
/// headline numerals, and no gradients or shadows.
struct ClaudeWrappedView: View {
    private let summary = WrappedSummary.mock
    @State private var shareImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                headlineStats
                modelBreakdown
                monthlyChart
                consistencyCard
                efficiencyCard
                shareSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wrapped")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: renderShareImage)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "gift")
                .font(.system(size: 32))
                .foregroundStyle(Constants.brandPrimary)
            Text("Your \(String(summary.year)) Wrapped")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("A year of building with Claude Code")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var headlineStats: some View {
        HStack(spacing: 16) {
            statTile(icon: "number", value: WrappedFormat.tokens(summary.totalTokens), label: "Tokens")
            statTile(icon: "dollarsign.circle", value: WrappedFormat.cost(summary.totalCostUSD), label: "Spent")
        }
    }

    private var modelBreakdown: some View {
        card {
            sectionHeader("Top models", systemImage: "chart.pie")
            ForEach(summary.modelShares) { share in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(share.modelName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(WrappedFormat.percent(share.fraction))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Constants.brandPrimary)
                    }
                    progressBar(fraction: share.fraction)
                    Text("\(WrappedFormat.tokens(share.tokens)) tokens · \(WrappedFormat.cost(share.costUSD))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var monthlyChart: some View {
        card {
            sectionHeader("By month", systemImage: "calendar")
            if let peak = summary.busiestMonth {
                Text("Busiest in \(WrappedFormat.monthAbbrev(peak.month)) · \(WrappedFormat.tokens(peak.tokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(summary.monthlyTokens) { point in
                BarMark(
                    x: .value("Month", WrappedFormat.monthAbbrev(point.month)),
                    y: .value("Tokens", point.tokens)
                )
                .foregroundStyle(
                    point.tokens == summary.peakMonthlyTokens
                        ? Constants.brandPrimary
                        : Constants.brandPrimary.opacity(0.35)
                )
                .cornerRadius(4)
            }
            .chartXScale(domain: summary.monthlyTokens.map { WrappedFormat.monthAbbrev($0.month) })
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(WrappedFormat.tokens(tokens))
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private var consistencyCard: some View {
        card {
            sectionHeader("Consistency", systemImage: "flame")
            HStack(spacing: 16) {
                miniStat("\(summary.activeDays)", "active days")
                miniStat("\(summary.longestStreakDays)", "day streak")
            }
            Text("Busiest day: \(WrappedFormat.longDate(summary.busiestDay)) · \(WrappedFormat.tokens(summary.busiestDayTokens)) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var efficiencyCard: some View {
        card {
            sectionHeader("Efficiency", systemImage: "bolt")
            HStack(spacing: 16) {
                miniStat(WrappedFormat.cost(summary.cacheSavingsUSD), "cache savings")
                miniStat(WrappedFormat.percent(summary.fastModeFraction), "fast mode")
            }
            Text("\(WrappedFormat.tokens(summary.cacheReadTokens)) tokens served from cache")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shareSection: some View {
        VStack(spacing: 12) {
            if let image = shareImage {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(
                        "My \(String(summary.year)) Claude Wrapped",
                        image: Image(uiImage: image)
                    )
                ) {
                    Label("Share your Wrapped", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Constants.brandPrimary, in: RoundedRectangle(cornerRadius: 16))
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            Text("Preview")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            WrappedShareCard(summary: summary)
                .frame(width: WrappedShareCard.size.width, height: WrappedShareCard.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.15))
                )
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Constants.brandPrimary)
            Text(title)
                .font(.headline)
        }
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Constants.brandPrimary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.brandPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Constants.brandPrimary)
                    .frame(width: max(0, geometry.size.width * fraction))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Share rendering

    private func renderShareImage() {
        let renderer = ImageRenderer(
            content: WrappedShareCard(summary: summary)
                .frame(width: WrappedShareCard.size.width, height: WrappedShareCard.size.height)
        )
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

#Preview {
    NavigationStack {
        ClaudeWrappedView()
    }
}
#endif
