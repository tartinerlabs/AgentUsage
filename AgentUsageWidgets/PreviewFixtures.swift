//
//  PreviewFixtures.swift
//  AgentUsageWidgets
//
//  Fabricated snapshots exist here and nowhere else. Everything below remains
//  DEBUG-only so shipping widgets never present sample values as real usage.
//

#if DEBUG
import AgentUsageKit
import Foundation

extension ProviderUsageSnapshot {
    static var widgetPreviewSnapshots: [ProviderUsageSnapshot] {
        let now = Date()
        return [
            ProviderUsageSnapshot(
                provider: .claude,
                windows: [
                    UsageWindow(
                        utilization: 45,
                        resetsAt: now.addingTimeInterval(2.5 * 60 * 60),
                        windowType: .session
                    ),
                    UsageWindow(
                        utilization: 32,
                        resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                        windowType: .opus
                    ),
                    UsageWindow(
                        utilization: 28,
                        resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                        windowType: .sonnet
                    ),
                ],
                planName: "Max",
                fetchedAt: now
            ),
            ProviderUsageSnapshot(
                provider: .codex,
                windows: [
                    UsageWindow(
                        utilization: 72,
                        resetsAt: now.addingTimeInterval(90 * 60),
                        windowType: .codexFiveHour
                    ),
                    UsageWindow(
                        utilization: 38,
                        resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
                        windowType: .codexWeekly
                    ),
                ],
                planName: "Plus",
                fetchedAt: now
            ),
            ProviderUsageSnapshot(
                provider: .cursor,
                windows: [
                    UsageWindow(
                        utilization: 92,
                        resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60),
                        windowID: "cursor.monthly.requests",
                        displayName: "Monthly agent requests",
                        totalDuration: 30 * 24 * 60 * 60
                    ),
                    UsageWindow(
                        utilization: 24,
                        resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60),
                        windowID: "cursor.api.usage",
                        displayName: "API usage",
                        totalDuration: 30 * 24 * 60 * 60
                    ),
                ],
                planName: "Pro",
                fetchedAt: now
            ),
        ]
    }
}

extension WidgetEntry {
    static func preview(provider: AgentUsageKit.Provider = .claude) -> WidgetEntry {
        let snapshots = ProviderUsageSnapshot.widgetPreviewSnapshots
        let window = snapshots.first(where: { $0.provider == provider })?.windows.first
        let selection = window.map {
            UsageActivitySelection(provider: provider, windowID: $0.windowID)
        }
        return WidgetEntry(date: .now, snapshots: snapshots, selection: selection)
    }

    static func previewNoData(provider: AgentUsageKit.Provider = .claude) -> WidgetEntry {
        let fallbackWindowID: UsageWindowID = switch provider {
        case .claude: "session"
        case .codex: "codexFiveHour"
        case .cursor: "cursor.monthly.requests"
        case .openCode, .openCodeGo, .grok: "custom"
        }
        return WidgetEntry(
            date: .now,
            snapshots: [],
            selection: UsageActivitySelection(provider: provider, windowID: fallbackWindowID)
        )
    }
}
#endif
