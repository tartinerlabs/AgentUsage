//
//  SparklineView.swift
//  ClaudeMeter
//
//  A compact sparkline chart for displaying usage trends in the menu bar
//

#if os(macOS)
import SwiftUI
import ClaudeMeterKit

/// A compact sparkline view for displaying usage trends
struct SparklineView: View {
    let values: [Double]
    let color: Color
    let height: CGFloat
    let width: CGFloat

    init(
        values: [Double],
        color: Color = .white,
        height: CGFloat = 10,
        width: CGFloat = 30
    ) {
        self.values = values
        self.color = color
        self.height = height
        self.width = width
    }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }

            let maxValue = max(values.max() ?? 100, 100) // Cap at 100% for usage
            let minValue = min(values.min() ?? 0, 0)
            let range = maxValue - minValue

            guard range > 0 else { return }

            let stepX = size.width / CGFloat(values.count - 1)

            var path = Path()

            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedValue = (value - minValue) / range
                let y = size.height - (normalizedValue * size.height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            )
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
