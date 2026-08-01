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
        if !entry.availableWindows.isEmpty {
            content(for: Array(entry.availableWindows.prefix(2)))
        } else {
            WidgetNoDataView(reason: entry.snapshot == nil ? .noData : .awaitingRefresh)
        }
    }

    private func content(for windows: [UsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetProviderIdentity(provider: WidgetDesign.provider, font: .headline)
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
    WidgetEntry.preview()
}

#Preview("Medium — No data", as: .systemMedium) {
    AgentUsageWidgets()
} timeline: {
    WidgetEntry.previewNoData()
}
#endif
