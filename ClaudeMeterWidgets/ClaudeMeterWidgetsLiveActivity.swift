//
//  ClaudeMeterWidgetsLiveActivity.swift
//  ClaudeMeterWidgets
//

import ActivityKit
import ClaudeMeterKit
import WidgetKit
import SwiftUI

// MARK: - Activity Attributes
// Note: This must match ClaudeMeterLiveActivityAttributes in the main app

struct ClaudeMeterLiveActivityAttributes: ActivityAttributes {
    /// Fixed properties set when activity starts
    var selectedMetric: String  // "Session", "Opus", or "Sonnet"

    /// Dynamic properties updated over time
    public struct ContentState: Codable, Hashable {
        var percentUsed: Int
        var timeUntilReset: String
        var statusRaw: String  // "onTrack", "warning", "critical"

        var status: UsageStatus {
            UsageStatus(rawValue: statusRaw) ?? .onTrack
        }
    }
}

// MARK: - Live Activity Widget

struct ClaudeMeterWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeMeterLiveActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenBannerView(context: context)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
                .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: context.state.status.icon)
                            .foregroundStyle(context.state.status.color)
                        Text(context.attributes.selectedMetric)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percentUsed)%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(context.state.status.color)
                        .padding(.horizontal, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(Color.secondary.opacity(0.3))
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(context.state.status.color)
                                    .frame(width: geometry.size.width * CGFloat(context.state.percentUsed) / 100)
                            }
                        }
                        .padding(.horizontal, 6)

                        HStack {
                            Text("\(context.state.percentUsed)% used")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Resets in \(context.state.timeUntilReset)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, 6)
                }

            } compactLeading: {
                Image(systemName: context.state.status.icon)
                    .foregroundStyle(context.state.status.color)

            } compactTrailing: {
                Text("\(context.state.percentUsed)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(context.state.status.color)

            } minimal: {
                Image(systemName: context.state.status.icon)
                    .foregroundStyle(context.state.status.color)
            }
            .keylineTint(context.state.status.color)
        }
    }
}

// MARK: - Lock Screen Banner View

struct LockScreenBannerView: View {
    let context: ActivityViewContext<ClaudeMeterLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(context.state.percentUsed) / 100)
                    .stroke(
                        context.state.status.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.attributes.selectedMetric)
                        .font(.headline)
                    Spacer()
                    Label(context.state.status.label, systemImage: context.state.status.icon)
                        .font(.caption)
                        .foregroundStyle(context.state.status.color)
                }

                HStack {
                    Text("\(context.state.percentUsed)%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(context.state.status.color)
                    Spacer()
                    Text("Resets in \(context.state.timeUntilReset)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Previews

extension ClaudeMeterLiveActivityAttributes {
    static var preview: ClaudeMeterLiveActivityAttributes {
        ClaudeMeterLiveActivityAttributes(selectedMetric: "Session")
    }
}

extension ClaudeMeterLiveActivityAttributes.ContentState {
    static var onTrack: ClaudeMeterLiveActivityAttributes.ContentState {
        ClaudeMeterLiveActivityAttributes.ContentState(
            percentUsed: 45,
            timeUntilReset: "2h 30m",
            statusRaw: "onTrack"
        )
    }

    static var warning: ClaudeMeterLiveActivityAttributes.ContentState {
        ClaudeMeterLiveActivityAttributes.ContentState(
            percentUsed: 72,
            timeUntilReset: "1h 15m",
            statusRaw: "warning"
        )
    }

    static var critical: ClaudeMeterLiveActivityAttributes.ContentState {
        ClaudeMeterLiveActivityAttributes.ContentState(
            percentUsed: 92,
            timeUntilReset: "45m",
            statusRaw: "critical"
        )
    }
}

#Preview("Notification", as: .content, using: ClaudeMeterLiveActivityAttributes.preview) {
    ClaudeMeterWidgetsLiveActivity()
} contentStates: {
    ClaudeMeterLiveActivityAttributes.ContentState.onTrack
    ClaudeMeterLiveActivityAttributes.ContentState.warning
    ClaudeMeterLiveActivityAttributes.ContentState.critical
}

