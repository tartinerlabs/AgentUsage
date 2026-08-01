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
        if !entry.availableWindows.isEmpty {
            content(for: entry.availableWindows)
        } else {
            WidgetNoDataView(reason: entry.unavailableReason, provider: entry.provider)
        }
    }

    private func content(for windows: [UsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: entry.provider, font: .headline)
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
    WidgetEntry.preview()
}

#Preview("Large — No data", as: .systemLarge) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
