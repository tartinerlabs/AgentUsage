//
//  WidgetUsageComponents.swift
//  AgentUsageWidgets
//
//  Compact WidgetKit adaptations of the shared provider-card visual system.
//

import AgentUsageKit
import SwiftUI
import WidgetKit

enum WidgetDesign {
    static let provider: AgentUsageKit.Provider = .claude
}

/// Uses the provider-card tint and border as the widget's root chrome. WidgetKit
/// supplies the outer shape and content margins, so the content does not create
/// a nested card of its own.
struct WidgetProviderBackground: View {
    let provider: AgentUsageKit.Provider

    var body: some View {
        ZStack {
            Color(.systemBackground)
            provider.accentColor.opacity(0.06)
            ContainerRelativeShape()
                .strokeBorder(provider.accentColor.opacity(0.15), lineWidth: 1)
        }
    }
}

/// Provider identity shared by every home-screen widget family.
struct WidgetProviderIdentity: View {
    let provider: AgentUsageKit.Provider
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: provider.iconName)
                .foregroundStyle(provider.accentColor)
                .widgetAccentable()
            Text(provider.displayName)
                .foregroundStyle(.primary)
        }
            .font(font)
            .fontWeight(.bold)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(provider.displayName)
    }
}

/// The widget-sized counterpart to `UsageRowView`: same title/reset hierarchy,
/// canonical Crail progress track, rounded usage figure, and semantic status.
struct WidgetUsageRow: View {
    let title: String
    let usage: UsageWindow
    let now: Date

    private var status: UsageStatus {
        usage.status(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(usage.resetDescription(from: now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            UsageProgressBar(usage: usage)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(usage.percentUsed)%")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                Text("used")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if usage.isUsingExtraUsage {
                    Text("+\(usage.extraUsagePercent)% extra")
                        .font(.footnote)
                        .foregroundStyle(AgentUsageColors.extraUsageAccent)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Label(status.label, systemImage: status.icon)
                    .font(.footnote)
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(usage.resetDescription(from: now))
    }

    private var accessibilityValue: String {
        var parts = ["\(usage.percentUsed) percent used", status.label]
        if usage.isUsingExtraUsage {
            parts.append("\(usage.extraUsagePercent) percent extra usage")
        }
        return parts.joined(separator: ", ")
    }
}
