//
//  WidgetNoDataView.swift
//  AgentUsageWidgets
//
//  What every widget family renders when no snapshot exists yet — before the
//  Mac has ever published to CloudKit, or on a fresh install with an empty App
//  Group cache. Previously these cases fell back to a hardcoded sample
//  snapshot, so a brand-new widget confidently reported usage the account had
//  never accrued. An empty state is the honest answer, and it also tells the
//  user the one thing that fixes it: the Mac has to run.
//

import SwiftUI
import WidgetKit

struct WidgetNoDataView: View {
    @Environment(\.widgetFamily) private var family

    /// Named so the copy stays identical across families and VoiceOver.
    private static let title = "No usage data"
    private static let hint = "Open AgentUsage on your Mac"

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

    /// Small: the ring is kept so the widget holds its familiar shape, drawn as
    /// an empty track with a dash where the percentage normally sits.
    private var compact: some View {
        VStack(spacing: 6) {
            emptyRing(size: 54, lineWidth: 6)

            Text(Self.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(Self.hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title)
        .accessibilityHint(Self.hint)
    }

    private var horizontal: some View {
        HStack(spacing: 14) {
            emptyRing(size: 48, lineWidth: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(Self.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title)
        .accessibilityHint(Self.hint)
    }

    private func emptyRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Text("—")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Accessory families

    /// Accessory families render monochrome, so the empty state leans on an
    /// empty gauge and a dash rather than a dimmed color.
    private var circular: some View {
        Gauge(value: 0) {
            Text("—")
                .font(.caption2)
                .fontWeight(.bold)
        } currentValueLabel: {
            Text("—")
                .font(.system(.body, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(Self.title)
        .accessibilityHint(Self.hint)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude Usage")
                .font(.headline)
            Text(Self.title)
                .font(.caption)
            Text(Self.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title)
        .accessibilityHint(Self.hint)
    }

    private var inline: some View {
        Text("Claude: no data")
            .accessibilityLabel(Self.title)
    }
}
