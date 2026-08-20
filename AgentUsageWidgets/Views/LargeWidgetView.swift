//
//  LargeWidgetView.swift
//  AgentUsageWidgets
//

import SwiftUI
import AgentUsageKit
import WidgetKit

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        let glances = entry.glanceWindows
        if glances.count >= 2 {
            overview(glances)
        } else if !entry.availableWindows.isEmpty, let provider = entry.provider {
            singleProvider(windows: entry.availableWindows, provider: provider)
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func overview(_ glances: [WidgetGlanceWindow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Spacer(minLength: 0)
                WidgetFreshnessLabel(
                    entry: entry,
                    fetchedAt: glances.map(\.fetchedAt).min(),
                    font: .caption
                )
            }

            VStack(spacing: glances.count > 3 ? 8 : 10) {
                ForEach(glances) { glance in
                    WidgetProviderGlanceRow(
                        provider: glance.provider,
                        usage: glance.window,
                        now: entry.date,
                        style: .regular
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func singleProvider(windows: [UsageWindow], provider: AgentUsageKit.Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: provider, font: .headline)
                Spacer(minLength: 8)
                WidgetFreshnessLabel(entry: entry, font: .caption)
            }

            VStack(spacing: windows.count > 4 ? 8 : 10) {
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
#Preview("Large", as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewOverview()
    WidgetEntry.preview(provider: .cursor)
}

#Preview("Large — No data", as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
