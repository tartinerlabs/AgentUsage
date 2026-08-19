//
//  EffortLevelsView.swift
//  AgentUsage
//
//  Shared effort-level distribution used by macOS and iOS provider surfaces.
//

import AgentUsageKit
import SwiftUI

struct EffortLevelsView: View {
    let provider: Provider
    let summary: EffortPeriodSummary
    var showsProviderHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsProviderHeader {
                providerHeader
            }

            if summary.totalSessionCount == 0 {
                unavailableMessage("No sessions in this period.")
            } else if summary.classifiedSessionCount == 0 {
                unavailableMessage("Effort metadata is unavailable for these sessions.")
            } else {
                ForEach(sortedLevels, id: \.level.rawValue) { levelCount in
                    EffortLevelRow(
                        levelCount: levelCount,
                        classifiedSessionCount: summary.classifiedSessionCount,
                        tint: AgentUsageColors.usageProgress
                    )
                }
            }

            if summary.totalSessionCount > 0 {
                Text(coverageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(coverageAccessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .foregroundStyle(AgentUsageColors.usageProgress)
                .accessibilityHidden(true)
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName) effort levels")
        .accessibilityAddTraits(.isHeader)
    }

    private var sortedLevels: [EffortLevelCount] {
        summary.levels
            .filter { $0.sessionCount > 0 }
            .sorted {
                if $0.level.sortOrder == $1.level.sortOrder {
                    return $0.level.rawValue < $1.level.rawValue
                }
                return $0.level.sortOrder < $1.level.sortOrder
            }
    }

    private func unavailableMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var coverageText: String {
        let classified = summary.classifiedSessionCount
        let unclassified = summary.unclassifiedSessionCount
        let total = summary.totalSessionCount

        if unclassified == 0 {
            return "All \(classified) \(sessionNoun(for: classified)) classified."
        }

        return "\(classified) of \(total) \(sessionNoun(for: total)) classified; "
            + "\(unclassified) omitted without effort metadata."
    }

    private var coverageAccessibilityLabel: String {
        let classified = summary.classifiedSessionCount
        let unclassified = summary.unclassifiedSessionCount
        let total = summary.totalSessionCount

        if unclassified == 0 {
            return "All \(classified) \(sessionNoun(for: classified)) classified"
        }

        return "\(classified) of \(total) \(sessionNoun(for: total)) classified. "
            + "\(unclassified) omitted without effort metadata"
    }

    private func sessionNoun(for count: Int) -> String {
        count == 1 ? "session" : "sessions"
    }
}

private struct EffortLevelRow: View {
    let levelCount: EffortLevelCount
    let classifiedSessionCount: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    levelLabel
                    Spacer(minLength: 8)
                    valueLabel
                }

                VStack(alignment: .leading, spacing: 2) {
                    levelLabel
                    valueLabel
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(levelCount.level.displayName) effort")
        .accessibilityValue(
            "\(percentageAccessibilityText), \(sessionText)"
        )
    }

    private var levelLabel: some View {
        Text(levelCount.level.displayName)
            .font(.subheadline.weight(.medium))
    }

    private var valueLabel: some View {
        Text("\(percentageText) · \(sessionText)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fraction: Double {
        guard classifiedSessionCount > 0 else { return 0 }
        return min(1, max(0, Double(levelCount.sessionCount) / Double(classifiedSessionCount)))
    }

    private var percentage: Double {
        fraction * 100
    }

    private var percentageText: String {
        if percentage > 0, percentage < 0.1 {
            return "<0.1%"
        }
        return percentage.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private var percentageAccessibilityText: String {
        if percentage > 0, percentage < 0.1 {
            return "less than 0.1 percent"
        }
        return percentage.formatted(.number.precision(.fractionLength(0...1))) + " percent"
    }

    private var sessionText: String {
        "\(levelCount.sessionCount) \(levelCount.sessionCount == 1 ? "session" : "sessions")"
    }
}
