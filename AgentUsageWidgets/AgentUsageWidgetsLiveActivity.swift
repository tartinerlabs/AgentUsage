//
//  AgentUsageWidgetsLiveActivity.swift
//  AgentUsageWidgets
//
import ActivityKit
import AgentUsageKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct AgentUsageWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentUsageLiveActivityAttributes.self) { context in
            LockScreenBannerView(context: context)
                .activityBackgroundTint(AgentUsageColors.usageProgress.opacity(0.08))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let displayState = context.state.displayState(isStale: context.isStale)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ProviderWindowLabel(
                        provider: context.state.provider,
                        windowName: context.state.windowName(fallback: context.attributes.selectedMetric)
                    )
                    .padding(.horizontal, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityValueView(state: context.state, displayState: displayState)
                        .padding(.horizontal, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedDetailView(state: context.state, displayState: displayState)
                        .padding(.horizontal, 12)
                }
            } compactLeading: {
                ProviderIcon(context.state.provider, size: 16, decorative: false)
                    .foregroundStyle(AgentUsageColors.usageProgress)
            } compactTrailing: {
                CompactValueView(state: context.state, displayState: displayState)
            } minimal: {
                MinimalActivityGauge(state: context.state, displayState: displayState)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        context.state.accessibilityDescription(
                            fallbackWindowName: context.attributes.selectedMetric,
                            displayState: displayState
                        )
                    )
            }
            .keylineTint(
                displayState == .available
                    ? context.state.status.color
                    : AgentUsageColors.usageProgress
            )
        }
    }
}

// MARK: - Lock Screen / Banner

private struct LockScreenBannerView: View {
    let context: ActivityViewContext<AgentUsageLiveActivityAttributes>

    private var displayState: LiveActivityDisplayState {
        context.state.displayState(isStale: context.isStale)
    }

    var body: some View {
        HStack(spacing: 16) {
            LiveActivityCircularGauge(state: context.state, displayState: displayState)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(context.state.provider)
                        .font(.headline)
                        .foregroundStyle(AgentUsageColors.usageProgress)
                    Spacer(minLength: 4)
                    if displayState == .available {
                        Label(context.state.status.label, systemImage: context.state.status.icon)
                            .font(.caption)
                            .foregroundStyle(context.state.status.color)
                    }
                }

                Text(context.state.windowName(fallback: context.attributes.selectedMetric))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if displayState == .available {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(context.state.percentageLabel)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        if context.state.isUsingExtraUsage {
                            Text("+\(context.state.extraUsagePercent)% extra")
                                .font(.caption2)
                                .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        }
                        Spacer(minLength: 8)
                        ResetCountdownView(state: context.state)
                    }
                } else {
                    NeutralStateLabel(
                        displayState: displayState,
                        fetchedAt: context.state.fetchedAt
                    )
                }
            }
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            context.state.accessibilityDescription(
                fallbackWindowName: context.attributes.selectedMetric,
                displayState: displayState
            )
        )
    }
}

private struct LiveActivityCircularGauge: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        Gauge(value: displayState == .available ? state.normalizedProgress : 0) {
            ProviderIcon(state.provider, size: 12)
                .foregroundStyle(AgentUsageColors.usageProgress)
        } currentValueLabel: {
            Image(systemName: displayState == .available ? state.status.icon : displayState.iconName)
                .font(.caption2)
                .foregroundStyle(displayState == .available ? state.status.color : .secondary)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(displayState == .available ? state.status.color : .secondary)
        .frame(width: 50, height: 50)
        .accessibilityHidden(true)
    }
}

// MARK: - Dynamic Island Components

private struct ProviderWindowLabel: View {
    let provider: AgentUsageKit.Provider
    let windowName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(provider)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AgentUsageColors.usageProgress)
            Text(windowName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(windowName)")
    }
}

private struct LiveActivityValueView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        if displayState == .available {
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.percentageLabel)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Image(systemName: state.status.icon)
                    .font(.caption)
                    .foregroundStyle(state.status.color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.usageAccessibilityDescription)
        } else {
            NeutralStateLabel(
                displayState: displayState,
                fetchedAt: state.fetchedAt,
                alignment: .trailing
            )
        }
    }
}

private struct CompactValueView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        if displayState == .available, state.percentUsed >= 100, let resetsAt = state.resetsAt {
            // Timer Text reports a huge ideal width; cap it so compact island stays around the camera.
            let end = max(resetsAt, .now)
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(state.status.color)
                .multilineTextAlignment(.trailing)
                .frame(width: 50, alignment: .trailing)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityLabel(state.resetAccessibilityDescription)
        } else if displayState == .available {
            HStack(spacing: 2) {
                Image(systemName: state.status.icon)
                Text(state.percentageLabel)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(state.status.color)
            .accessibilityLabel(state.usageAccessibilityDescription)
        } else {
            Image(systemName: displayState.iconName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(displayState.message)
        }
    }
}

private struct ExpandedDetailView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        if displayState == .available {
            VStack(spacing: 8) {
                Gauge(value: state.normalizedProgress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(state.status.color)
                .accessibilityHidden(true)

                HStack {
                    Label(state.status.label, systemImage: state.status.icon)
                        .foregroundStyle(state.status.color)
                    if state.isUsingExtraUsage {
                        Text("+\(state.extraUsagePercent)% extra")
                            .foregroundStyle(AgentUsageColors.extraUsageAccent)
                    }
                    Spacer()
                    ResetCountdownView(state: state)
                }
                .font(.caption2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.usageAccessibilityDescription)
            .accessibilityHint(state.resetAccessibilityDescription)
        } else {
            NeutralStateLabel(displayState: displayState, fetchedAt: state.fetchedAt)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MinimalActivityGauge: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        Gauge(value: displayState == .available ? state.normalizedProgress : 0) {
            ProviderIcon(state.provider, size: 10)
        } currentValueLabel: {
            Image(systemName: displayState == .available ? state.status.icon : displayState.iconName)
                .font(.system(size: 7, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(displayState == .available ? state.status.color : .secondary)
    }
}

private struct ResetCountdownView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            if let resetsAt = state.resetsAt {
                Text("Resets in")
                Text(resetsAt, style: .timer)
                    .monospacedDigit()
            } else if state.timeUntilReset == "now" {
                Text("Resets now")
            } else {
                Text("Resets in \(state.timeUntilReset)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct NeutralStateLabel: View {
    let displayState: LiveActivityDisplayState
    var fetchedAt: Date? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Label(displayState.message, systemImage: displayState.iconName)
                .lineLimit(1)
            if let fetchedAt {
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(fetchedAt, style: .relative)
                }
                .font(.caption2)
                .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayState.message)
        .accessibilityValue(freshnessAccessibilityValue)
    }

    private var freshnessAccessibilityValue: String {
        guard let fetchedAt else { return "" }
        return "Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Presentation State

private enum LiveActivityDisplayState: Equatable {
    case available
    case awaitingRefresh
    case unavailable
    case reset

    var message: String {
        switch self {
        case .available: ""
        case .awaitingRefresh: "Awaiting refresh"
        case .unavailable: "Usage unavailable"
        case .reset: "Limit reset"
        }
    }

    var iconName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .awaitingRefresh: "arrow.clockwise"
        case .unavailable: "exclamationmark.circle"
        case .reset: "checkmark.circle.fill"
        }
    }
}

private extension AgentUsageLiveActivityAttributes.ContentState {
    var percentageLabel: String {
        "\(max(0, percentUsed))%"
    }

    var isUsingExtraUsage: Bool {
        percentUsed > 100
    }

    var extraUsagePercent: Int {
        max(0, percentUsed - 100)
    }

    var usageAccessibilityDescription: String {
        var parts = ["\(percentageLabel) used", status.label]
        if isUsingExtraUsage {
            parts.append("\(extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }

    func windowName(fallback: String) -> String {
        guard let windowDisplayName, !windowDisplayName.isEmpty else { return fallback }
        return windowDisplayName
    }

    func displayState(isStale: Bool) -> LiveActivityDisplayState {
        if availability == .reset {
            return .reset
        }
        if availability == .unavailable {
            return .unavailable
        }
        if availability == .awaitingRefresh || isStale {
            return .awaitingRefresh
        }
        return .available
    }

    func accessibilityDescription(
        fallbackWindowName: String,
        displayState: LiveActivityDisplayState
    ) -> String {
        let prefix = "\(provider.displayName), \(windowName(fallback: fallbackWindowName))"
        switch displayState {
        case .available:
            var parts = [prefix, "\(percentageLabel) used", status.label]
            if isUsingExtraUsage {
                parts.append("\(extraUsagePercent) percent extra usage")
            }
            parts.append(resetAccessibilityDescription)
            return parts.joined(separator: ", ")
        case .awaitingRefresh, .unavailable, .reset:
            var parts = [prefix, displayState.message]
            if let fetchedAt {
                parts.append("updated at \(fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
            return parts.joined(separator: ", ")
        }
    }

    var resetAccessibilityDescription: String {
        if let resetsAt {
            return "resets at \(resetsAt.formatted(date: .omitted, time: .shortened))"
        }
        if timeUntilReset == "now" {
            return "resets now"
        }
        return "resets in \(timeUntilReset)"
    }
}

// MARK: - Previews

#if DEBUG
private extension AgentUsageLiveActivityAttributes {
    static var preview: AgentUsageLiveActivityAttributes {
        AgentUsageLiveActivityAttributes(selectedMetric: "Current session")
    }
}

private extension AgentUsageLiveActivityAttributes.ContentState {
    static func preview(
        provider: AgentUsageKit.Provider,
        windowID: UsageWindowID,
        windowName: String,
        percentUsed: Int,
        status: UsageStatus,
        availability: UsageActivityAvailability = .available
    ) -> Self {
        let resetsAt = Date().addingTimeInterval(2.5 * 60 * 60)
        return Self(
            percentUsed: percentUsed,
            timeUntilReset: "2h 30m",
            statusRaw: status.rawValue,
            selection: UsageActivitySelection(provider: provider, windowID: windowID),
            windowDisplayName: windowName,
            resetsAt: resetsAt,
            fetchedAt: Date(),
            availabilityRaw: availability.rawValue
        )
    }

    static let claudePreview = preview(
        provider: .claude,
        windowID: "session",
        windowName: "Current session",
        percentUsed: 45,
        status: .onTrack
    )

    static let codexPreview = preview(
        provider: .codex,
        windowID: "codexFiveHour",
        windowName: "5-hour limit",
        percentUsed: 72,
        status: .warning
    )

    static let cursorPreview = preview(
        provider: .cursor,
        windowID: "cursor-custom-monthly-requests",
        windowName: "Monthly included agent requests",
        percentUsed: 92,
        status: .critical
    )
}

#Preview("Providers", as: .content, using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.claudePreview
    AgentUsageLiveActivityAttributes.ContentState.codexPreview
    AgentUsageLiveActivityAttributes.ContentState.cursorPreview
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.codexPreview
}

#Preview("Compact", as: .dynamicIsland(.compact), using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .cursor,
        windowID: "cursor-custom-monthly-requests",
        windowName: "Monthly requests",
        percentUsed: 100,
        status: .critical
    )
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .claude,
        windowID: "session",
        windowName: "Current session",
        percentUsed: 0,
        status: .onTrack
    )
}

#Preview("Refresh and unavailable", as: .content, using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .codex,
        windowID: "codexWeekly",
        windowName: "Weekly limit",
        percentUsed: 80,
        status: .warning,
        availability: .awaitingRefresh
    )
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .cursor,
        windowID: "cursor-custom-monthly-requests",
        windowName: "Monthly requests",
        percentUsed: 80,
        status: .warning,
        availability: .unavailable
    )
}

#Preview("Progress bounds and long label", as: .content, using: AgentUsageLiveActivityAttributes.preview) {
    AgentUsageWidgetsLiveActivity()
} contentStates: {
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .claude,
        windowID: "session",
        windowName: "Current session",
        percentUsed: 0,
        status: .onTrack
    )
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .codex,
        windowID: "codexWeekly",
        windowName: "Weekly limit",
        percentUsed: 100,
        status: .critical
    )
    AgentUsageLiveActivityAttributes.ContentState.preview(
        provider: .cursor,
        windowID: "cursor-custom-monthly-requests",
        windowName: "Monthly included agent requests with a deliberately long provider label",
        percentUsed: 135,
        status: .critical
    )
}
#endif
