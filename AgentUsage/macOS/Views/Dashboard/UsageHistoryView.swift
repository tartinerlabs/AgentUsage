//
//  UsageHistoryView.swift
//  AgentUsage
//
//  Displays historical usage trends using Swift Charts
//

#if os(macOS)
import SwiftUI
import Charts
import AgentUsageKit

/// Daily peak utilization over time, for every provider or one at a time.
///
/// Designed to sit inside the dashboard's section chrome, so it draws no card
/// background of its own.
struct UsageHistoryView: View {
    let history: ProviderUsageHistory

    @State private var selectedDays: Int = 7
    /// `nil` shows every provider, collapsed to its worst window per day.
    @State private var selectedProvider: Provider?

    /// Hues for the per-window breakdown. The all-providers chart uses Crail
    /// for every series; isolate a provider with the picker to read windows.
    private static let windowPalette: [Color] = [.blue, .teal, .indigo, .cyan, .mint]

    private static let periods = [7, 14, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls

            if series.isEmpty {
                emptyState
            } else {
                chartView
                statsView
            }
        }
    }

    // MARK: - Data

    /// History narrowed to the selected period. Everything on screen derives
    /// from this, so the period picker moves the chart and the statistics
    /// together.
    private var visibleHistory: ProviderUsageHistory {
        history.last(selectedDays)
    }

    private var series: [ProviderUsageHistory.Series] {
        if let selectedProvider {
            return visibleHistory.seriesByWindow(for: selectedProvider)
        }
        return visibleHistory.seriesByProvider()
    }

    private var stats: ProviderUsageHistory.Stats {
        visibleHistory.stats(for: selectedProvider)
    }

    private var seriesColors: [Color] {
        if selectedProvider != nil {
            return series.indices.map { Self.windowPalette[$0 % Self.windowPalette.count] }
        }
        return series.map { _ in Constants.brandPrimary }
    }

    private var scopeName: String {
        selectedProvider?.displayName ?? "all providers"
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            if history.providers.count > 1 {
                Picker("Provider", selection: $selectedProvider) {
                    Text("All").tag(Provider?.none)
                    ForEach(history.providers) { provider in
                        Text(provider.displayName).tag(Provider?.some(provider))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Select provider")
            }

            Spacer(minLength: 12)

            Picker("Period", selection: $selectedDays) {
                ForEach(Self.periods, id: \.self) { days in
                    Text("\(days) Days").tag(days)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .accessibilityLabel("Select time period")
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Peak", point.utilization)
                    )
                    .foregroundStyle(by: .value("Series", line.label))
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                }
            }

            RuleMark(y: .value("Warning", ProviderUsageHistory.warningThreshold))
                .foregroundStyle(UsageStatus.warning.color.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .annotation(position: .top, alignment: .trailing) {
                    Label(
                        "Warning \(Int(ProviderUsageHistory.warningThreshold))%",
                        systemImage: UsageStatus.warning.icon
                    )
                        .font(.caption2)
                        .foregroundStyle(UsageStatus.warning.color)
                }

            RuleMark(y: .value("Critical", ProviderUsageHistory.criticalThreshold))
                .foregroundStyle(UsageStatus.critical.color.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .annotation(position: .top, alignment: .trailing) {
                    Label(
                        "Critical \(Int(ProviderUsageHistory.criticalThreshold))%",
                        systemImage: UsageStatus.critical.icon
                    )
                        .font(.caption2)
                        .foregroundStyle(UsageStatus.critical.color)
                }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                    }
                }
            }
        }
        .chartXAxis {
            // A daily stride is unreadable beyond a week, so thin the labels out
            // as the period grows.
            AxisMarks(values: .stride(by: .day, count: axisStride)) { value in
                AxisGridLine()
                AxisValueLabel(format: selectedDays > 7
                    ? .dateTime.month(.abbreviated).day()
                    : .dateTime.weekday(.abbreviated))
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.label), range: seriesColors)
        .chartLegend(position: .bottom)
        .frame(height: 200)
        .accessibilityLabel("Usage trend chart for \(scopeName) over the last \(selectedDays) days")
    }

    private var axisStride: Int {
        switch selectedDays {
        case ...7: 1
        case ...14: 2
        default: 5
        }
    }

    // MARK: - Statistics

    private var statsView: some View {
        HStack(spacing: 24) {
            statItem(
                title: "Average Peak",
                value: percent(stats.average),
                trend: stats.trend
            )

            Divider()
                .frame(height: 40)

            statItem(
                title: "Highest Peak",
                value: percent(stats.peak),
                trend: nil
            )

            Divider()
                .frame(height: 40)

            statItem(
                title: "Critical Days",
                value: "\(stats.criticalDays)",
                trend: nil
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage statistics for \(scopeName) over the last \(selectedDays) days")
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func statItem(title: String, value: String, trend: UsageTrend?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let trend {
                    Image(systemName: trend.icon)
                        .font(.caption)
                        .foregroundStyle(trendColor(trend))
                        .accessibilityLabel(trend.accessibilityLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendColor(_ trend: UsageTrend) -> Color {
        switch trend {
        case .increasing: return .orange
        case .decreasing: return .green
        case .stable: return .secondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.headline)
            Text("Daily peaks appear here as your providers report usage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No usage history available yet")
    }
}

#Preview {
    UsageHistoryView(history: .sample)
        .frame(width: 520)
        .padding()
}

#Preview("Empty") {
    UsageHistoryView(history: .empty)
        .frame(width: 520)
        .padding()
}
#endif
