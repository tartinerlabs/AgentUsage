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
        } else if let glance = glances.first {
            singleProvider(
                windows: entry.liveWindows(for: glance.provider),
                provider: glance.provider,
                fetchedAt: glance.fetchedAt
            )
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func overview(_ glances: [WidgetGlanceWindow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fetchedAt = glances.map(\.fetchedAt).max(), entry.isStale(fetchedAt: fetchedAt) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Spacer(minLength: 0)
                    WidgetFreshnessLabel(entry: entry, fetchedAt: fetchedAt, font: .widgetCaption)
                }
            }

            // Large adds a second layer of the same content (HIG: larger sizes
            // support additional layers). Smaller phones fall back to one
            // window per provider rather than clipping.
            ViewThatFits(in: .vertical) {
                providerList(glances, secondaryWindows: true)
                providerList(glances, secondaryWindows: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func providerList(_ glances: [WidgetGlanceWindow], secondaryWindows: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(glances) { glance in
                VStack(alignment: .leading, spacing: 5) {
                    WidgetProviderGlanceRow(
                        provider: glance.provider,
                        usage: glance.window,
                        now: entry.date,
                        style: .regular
                    )
                    if secondaryWindows {
                        ForEach(secondaryWindow(for: glance), id: \.windowID) { usage in
                            WidgetSecondaryWindowRow(usage: usage, now: entry.date)
                        }
                    }
                }
            }
        }
    }

    /// The next live window after the glance, if the provider publishes more than one.
    private func secondaryWindow(for glance: WidgetGlanceWindow) -> [UsageWindow] {
        Array(
            entry.liveWindows(for: glance.provider)
                .filter { $0.windowID != glance.window.windowID }
                .prefix(1)
        )
    }

    private func singleProvider(
        windows: [UsageWindow],
        provider: AgentUsageKit.Provider,
        fetchedAt: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: provider, font: .headline)
                Spacer(minLength: 8)
                if entry.isStale(fetchedAt: fetchedAt) {
                    WidgetFreshnessLabel(entry: entry, fetchedAt: fetchedAt, font: .widgetCaption)
                }
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
