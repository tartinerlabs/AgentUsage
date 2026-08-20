//
//  WidgetNoDataView.swift
//  AgentUsageWidgets
//
//  Honest unavailable states for every widget family.
//

import AgentUsageKit
import SwiftUI
import WidgetKit

struct WidgetNoDataView: View {
    @Environment(\.widgetFamily) private var family

    let reason: WidgetUnavailableReason
    let provider: AgentUsageKit.Provider?

    init(
        reason: WidgetUnavailableReason = .noData,
        provider: AgentUsageKit.Provider? = nil
    ) {
        self.reason = reason
        self.provider = provider
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .systemMedium, .systemLarge:
            horizontal
        default:
            compact
        }
    }

    // MARK: - System families

    private var compact: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let provider {
                WidgetProviderIdentity(provider: provider, font: .caption)
            }
            Spacer(minLength: 0)
            unavailableLabel
                .font(.headline)
            Text(copy.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityUnavailableState(provider: provider, copy: copy)
    }

    private var horizontal: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider {
                WidgetProviderIdentity(provider: provider, font: .headline)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Image(systemName: copy.iconName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(copy.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityUnavailableState(provider: provider, copy: copy)
    }

    private var unavailableLabel: some View {
        Label(copy.title, systemImage: copy.iconName)
            .foregroundStyle(.primary)
    }

    // MARK: - Accessory families

    private var circular: some View {
        Gauge(value: 0) {
            Group {
                if let provider {
                    ProviderIcon(provider, size: 12)
                } else {
                    Image(systemName: "chart.bar.xaxis")
                }
            }
            .accessibilityHidden(true)
        } currentValueLabel: {
            Image(systemName: copy.iconName)
                .font(.caption)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .accessibilityUnavailableState(provider: provider, copy: copy)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let provider {
                Label(provider)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Label(copy.title, systemImage: copy.iconName)
                .font(.caption)
                .fontWeight(.semibold)
            Text(copy.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityUnavailableState(provider: provider, copy: copy)
    }

    private var inline: some View {
        Group {
            if let provider {
                Text("\(provider.markImage) \(provider.displayName): \(copy.inlineTitle)")
            } else {
                Text(copy.inlineTitle)
            }
        }
        .accessibilityUnavailableState(provider: provider, copy: copy)
    }

    private var copy: WidgetUnavailableCopy {
        switch reason {
        case .noData:
            WidgetUnavailableCopy(
                title: "No usage data",
                inlineTitle: "no data",
                hint: "Open Agent Usage on your Mac",
                iconName: "chart.bar.xaxis"
            )
        case .windowUnavailable:
            WidgetUnavailableCopy(
                title: "Window unavailable",
                inlineTitle: "window unavailable",
                hint: "Choose another usage window",
                iconName: "questionmark.circle"
            )
        case .awaitingRefresh:
            WidgetUnavailableCopy(
                title: "Awaiting refresh",
                inlineTitle: "awaiting refresh",
                hint: "Open Agent Usage on your Mac",
                iconName: "arrow.clockwise"
            )
        }
    }
}

private struct WidgetUnavailableCopy {
    let title: String
    let inlineTitle: String
    let hint: String
    let iconName: String
}

private extension View {
    func accessibilityUnavailableState(
        provider: AgentUsageKit.Provider?,
        copy: WidgetUnavailableCopy
    ) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(
                provider.map { "\($0.displayName), \(copy.title)" } ?? copy.title
            )
            .accessibilityHint(copy.hint)
    }
}
