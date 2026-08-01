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
                .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
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
                Image(systemName: context.state.provider.iconName)
                    .foregroundStyle(context.state.provider.accentColor)
                    .accessibilityLabel(context.state.provider.displayName)
            } compactTrailing: {
                CompactValueView(state: context.state, displayState: displayState)
            } minimal: {
                Image(systemName: context.state.provider.iconName)
                    .foregroundStyle(context.state.provider.accentColor)
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
                    : context.state.provider.accentColor
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
            ProgressRing(state: context.state, displayState: displayState)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(context.state.provider.displayName, systemImage: context.state.provider.iconName)
                        .font(.headline)
                        .foregroundStyle(context.state.provider.accentColor)
                    Spacer(minLength: 4)
                    if displayState == .available {
                        Label(context.state.status.label, systemImage: context.state.status.icon)
                            .font(.caption)
                            .foregroundStyle(context.state.status.color)
                    }
                }

                Text(context.state.windowName(fallback: context.attributes.selectedMetric))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if displayState == .available {
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.state.percentageLabel)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(context.state.status.color)
                        Spacer(minLength: 8)
                        ResetCountdownView(state: context.state)
                    }
                } else {
                    NeutralStateLabel(displayState: displayState)
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

private struct ProgressRing: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 6)

            if displayState == .available {
                Circle()
                    .trim(from: 0, to: state.normalizedProgress)
                    .stroke(
                        state.status.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: state.provider.iconName)
                .font(.headline)
                .foregroundStyle(state.provider.accentColor)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Dynamic Island Components

private struct ProviderWindowLabel: View {
    let provider: AgentUsageKit.Provider
    let windowName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(provider.displayName, systemImage: provider.iconName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(provider.accentColor)
            Text(windowName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct LiveActivityValueView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        if displayState == .available {
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.percentageLabel)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(state.status.color)
                Image(systemName: state.status.icon)
                    .font(.caption)
                    .foregroundStyle(state.status.color)
                    .accessibilityLabel(state.status.label)
            }
        } else {
            NeutralStateLabel(displayState: displayState, alignment: .trailing)
        }
    }
}

private struct CompactValueView: View {
    let state: AgentUsageLiveActivityAttributes.ContentState
    let displayState: LiveActivityDisplayState

    var body: some View {
        if displayState == .available {
            HStack(spacing: 2) {
                Image(systemName: state.status.icon)
                Text(state.percentageLabel)
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(state.status.color)
            .accessibilityLabel("\(state.status.label), \(state.percentageLabel) used")
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
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.3))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(state.status.color)
                            .frame(width: geometry.size.width * state.normalizedProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Label(state.status.label, systemImage: state.status.icon)
                        .foregroundStyle(state.status.color)
                    Spacer()
                    ResetCountdownView(state: state)
                }
                .font(.caption2)
            }
        } else {
            NeutralStateLabel(displayState: displayState)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Image(systemName: displayState.iconName)
            Text(displayState.message)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Presentation State

private enum LiveActivityDisplayState: Equatable {
    case available
    case awaitingRefresh
    case unavailable

    var message: String {
        switch self {
        case .available: ""
        case .awaitingRefresh: "Awaiting refresh"
        case .unavailable: "Usage unavailable"
        }
    }

    var iconName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .awaitingRefresh: "arrow.clockwise"
        case .unavailable: "exclamationmark.circle"
        }
    }
}

private extension AgentUsageLiveActivityAttributes.ContentState {
    var percentageLabel: String {
        "\(max(0, percentUsed))%"
    }

    func windowName(fallback: String) -> String {
        guard let windowDisplayName, !windowDisplayName.isEmpty else { return fallback }
        return windowDisplayName
    }

    func displayState(isStale: Bool) -> LiveActivityDisplayState {
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
            let resetDescription: String
            if let resetsAt {
                resetDescription = "resets at \(resetsAt.formatted(date: .omitted, time: .shortened))"
            } else if timeUntilReset == "now" {
                resetDescription = "resets now"
            } else {
                resetDescription = "resets in \(timeUntilReset)"
            }
            return "\(prefix), \(percentageLabel) used, \(status.label), \(resetDescription)"
        case .awaitingRefresh, .unavailable:
            return "\(prefix), \(displayState.message)"
        }
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
