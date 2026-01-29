//
//  UsageHistoryView.swift
//  ClaudeMeter
//
//  Displays historical usage trends using Swift Charts
//

#if os(macOS)
import SwiftUI
import Charts
import ClaudeMeterKit

struct UsageHistoryView: View {
    let history: UsageHistory
    @State private var selectedDays: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with period selector
            HStack {
                Text("Usage Trends")
                    .font(.headline)

                Spacer()

                Picker("Period", selection: $selectedDays) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel("Select time period")
            }

            if records.isEmpty {
                emptyState
            } else {
                chartView
                statsView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    private var records: [DailyUsageRecord] {
        history.last(selectedDays)
    }

    private var chartView: some View {
        Chart {
            ForEach(records) { record in
                LineMark(
                    x: .value("Date", record.date, unit: .day),
                    y: .value("Usage", record.peakOpusUtilization)
                )
                .foregroundStyle(by: .value("Type", "All Models"))
                .symbol(Circle())
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", record.date, unit: .day),
                    y: .value("Usage", record.peakSessionUtilization)
                )
                .foregroundStyle(by: .value("Type", "Session"))
                .symbol(Circle())
                .interpolationMethod(.catmullRom)

                if let sonnet = record.peakSonnetUtilization {
                    LineMark(
                        x: .value("Date", record.date, unit: .day),
                        y: .value("Usage", sonnet)
                    )
                    .foregroundStyle(by: .value("Type", "Sonnet"))
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                }
            }

            // Warning threshold line
            RuleMark(y: .value("Warning", 75))
                .foregroundStyle(.orange.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

            // Critical threshold line
            RuleMark(y: .value("Critical", 90))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
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
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .chartForegroundStyleScale([
            "Session": Color.blue,
            "All Models": Color.orange,
            "Sonnet": Color.purple
        ])
        .chartLegend(position: .bottom)
        .frame(height: 200)
        .accessibilityLabel("Usage trend chart for the last \(selectedDays) days")
    }

    private var statsView: some View {
        HStack(spacing: 24) {
            statItem(
                title: "Avg Session",
                value: "\(Int(history.averageSessionUtilization))%",
                trend: UsageTrend.calculate(from: records, keyPath: \.peakSessionUtilization)
            )

            Divider()
                .frame(height: 40)

            statItem(
                title: "Avg All Models",
                value: "\(Int(history.averageOpusUtilization))%",
                trend: UsageTrend.calculate(from: records, keyPath: \.peakOpusUtilization)
            )

            Divider()
                .frame(height: 40)

            statItem(
                title: "Critical Days",
                value: "\(history.criticalDays.count)",
                trend: nil
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage statistics")
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
            Text("Usage data will appear here as you use Claude")
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
        .frame(width: 500)
        .padding()
}

#Preview("Empty") {
    UsageHistoryView(history: .empty)
        .frame(width: 500)
        .padding()
}
#endif
