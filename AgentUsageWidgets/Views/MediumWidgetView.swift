//
//  MediumWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        let glances = entry.glanceWindows
        if glances.count >= 2 {
            overview(glances)
        } else if !entry.availableWindows.isEmpty, let provider = entry.provider {
            singleProvider(windows: Array(entry.availableWindows.prefix(2)), provider: provider)
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func overview(_ glances: [WidgetGlanceWindow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Spacer(minLength: 0)
                WidgetFreshnessLabel(
                    entry: entry,
                    fetchedAt: glances.map(\.fetchedAt).min()
                )
            }

            VStack(spacing: 8) {
                ForEach(glances) { glance in
                    WidgetProviderGlanceRow(
                        provider: glance.provider,
                        usage: glance.window,
                        now: entry.date,
                        style: .compact
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func singleProvider(windows: [UsageWindow], provider: AgentUsageKit.Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: provider, font: .headline)
                Spacer(minLength: 8)
                WidgetFreshnessLabel(entry: entry)
            }

            VStack(spacing: 8) {
                ForEach(windows, id: \.windowID) { usage in
                    WidgetUsageRow(
                        title: usage.displayName,
                        usage: usage,
                        now: entry.date
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Medium", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.preview(provider: .codex)
}

#Preview("Medium — No data", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
