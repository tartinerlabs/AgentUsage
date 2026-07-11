//
//  SparklineView.swift
//  AgentUsage
//
//  A compact sparkline chart for displaying usage trends in the menu bar
//

#if os(macOS)
import SwiftUI
import AgentUsageKit

/// A compact sparkline view for displaying usage trends
struct SparklineView: View {
    enum Style {
        case line
        case bars
    }

    let values: [Double]
    let color: Color
    let height: CGFloat
    let width: CGFloat
    let style: Style
    /// When true, scale to the data's own max (for costs); when false, cap at 100 (for utilization %).
    let autoScale: Bool

    init(
        values: [Double],
        color: Color = .white,
        height: CGFloat = 10,
        width: CGFloat = 30,
        style: Style = .line,
        autoScale: Bool = false
    ) {
        self.values = values
        self.color = color
        self.height = height
        self.width = width
        self.style = style
        self.autoScale = autoScale
    }

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }

            let maxValue = autoScale ? max(values.max() ?? 0, 0.0001) : max(values.max() ?? 100, 100)
            let minValue = autoScale ? 0 : min(values.min() ?? 0, 0)
            let range = maxValue - minValue
            guard range > 0 else { return }

            switch style {
            case .line:
                guard values.count >= 2 else { return }
                let stepX = size.width / CGFloat(values.count - 1)
                var path = Path()
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = size.height - ((value - minValue) / range * size.height)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

            case .bars:
                let gap: CGFloat = values.count > 40 ? 0.5 : 1.5
                let slot = size.width / CGFloat(values.count)
                let barWidth = max(slot - gap, 0.5)
                for (index, value) in values.enumerated() {
                    let normalized = (value - minValue) / range
                    let barHeight = max(normalized * size.height, value > 0 ? 1 : 0)
                    let x = CGFloat(index) * slot
                    let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 1.5)),
                        with: .color(value > 0 ? color : color.opacity(0.25))
                    )
                }
            }
        }
        .frame(width: width, height: height)
    }
}

/// Extension to create sparklines from daily usage records
extension SparklineView {
    /// Create a sparkline from daily usage records for session utilization
    static func session(from records: [DailyUsageRecord], width: CGFloat = 30, height: CGFloat = 10) -> SparklineView {
        SparklineView(
            values: records.map(\.peakSessionUtilization),
            color: .white.opacity(0.8),
            height: height,
            width: width
        )
    }

    /// Create a sparkline from daily usage records for opus utilization
    static func opus(from records: [DailyUsageRecord], width: CGFloat = 30, height: CGFloat = 10) -> SparklineView {
        SparklineView(
            values: records.map(\.peakOpusUtilization),
            color: .white.opacity(0.8),
            height: height,
            width: width
        )
    }

    /// Create a sparkline from daily usage records for sonnet utilization
    static func sonnet(from records: [DailyUsageRecord], width: CGFloat = 30, height: CGFloat = 10) -> SparklineView? {
        let sonnetValues = records.compactMap(\.peakSonnetUtilization)
        guard sonnetValues.count >= 2 else { return nil }

        return SparklineView(
            values: sonnetValues,
            color: .white.opacity(0.8),
            height: height,
            width: width
        )
    }

    /// Create a sparkline from daily usage records for fable utilization
    static func fable(from records: [DailyUsageRecord], width: CGFloat = 30, height: CGFloat = 10) -> SparklineView? {
        let fableValues = records.compactMap(\.peakFableUtilization)
        guard fableValues.count >= 2 else { return nil }

        return SparklineView(
            values: fableValues,
            color: .white.opacity(0.8),
            height: height,
            width: width
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        // Sample sparkline with increasing trend
        SparklineView(
            values: [20, 25, 30, 35, 45, 50, 60],
            color: .green
        )

        // Sample sparkline with decreasing trend
        SparklineView(
            values: [80, 70, 65, 55, 45, 40, 35],
            color: .orange
        )

        // Sample sparkline with stable trend
        SparklineView(
            values: [45, 48, 42, 47, 44, 46, 45],
            color: .blue
        )
    }
    .padding()
    .background(Color.black)
}
#endif
