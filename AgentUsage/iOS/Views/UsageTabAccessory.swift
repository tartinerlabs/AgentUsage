//
//  UsageTabAccessory.swift
//  AgentUsage
//
//  The iOS 26 tab-bar accessory: a "now playing" strip for the most urgent live
//  rate window, the way Music keeps the current track above the tab bar. It stays
//  visible from every tab, collapses beside the minimized tab bar on scroll, and
//  tapping it opens that provider's full detail as a sheet.
//

#if os(iOS)
import AgentUsageKit
import SwiftUI

extension UsageViewModel {
    /// The single most urgent live window across every visible provider — the
    /// same pick an unconfigured Small widget makes, so the accessory and the
    /// Home Screen agree on what matters right now.
    func mostUrgentGlance(now: Date) -> WidgetGlanceWindow? {
        let snapshots = availableProviders.compactMap { usageSnapshot(for: $0) }
        guard let selection = UsageActivitySelection.mostUrgent(in: snapshots, now: now),
              let snapshot = snapshots.first(where: { $0.provider == selection.provider }),
              let window = snapshot.liveWindows(now: now).first(where: { $0.windowID == selection.windowID })
        else {
            return nil
        }
        return WidgetGlanceWindow(
            provider: snapshot.provider,
            window: window,
            fetchedAt: snapshot.fetchedAt,
            lastUsedAt: snapshot.lastUsedAt
        )
    }
}

@available(iOS 26.1, *)
struct UsageTabAccessory: View {
    let onSelect: (Provider) -> Void

    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        // Countdowns are minute-granularity, matching `ProviderSectionView`.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let glance = viewModel.mostUrgentGlance(now: context.date) {
                Button {
                    onSelect(glance.provider)
                } label: {
                    UsageTabAccessoryLabel(glance: glance, now: context.date)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows \(glance.provider.displayName) usage details")
            }
        }
    }
}

@available(iOS 26.1, *)
private struct UsageTabAccessoryLabel: View {
    let glance: WidgetGlanceWindow
    let now: Date

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var window: UsageWindow { glance.window }
    private var status: UsageStatus { window.status(from: now) }

    var body: some View {
        Group {
            if placement == .inline {
                inlineContent
            } else {
                expandedContent
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Beside the minimized tab bar there's room for a glyph and a number only.
    private var inlineContent: some View {
        HStack(spacing: 6) {
            ProviderIcon(glance.provider, size: 16)
            Text("\(window.percentUsed)%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Image(systemName: status.icon)
                .font(.caption)
                .foregroundStyle(status.color)
        }
    }

    private var expandedContent: some View {
        HStack(spacing: 12) {
            ProviderIcon(glance.provider, size: 20)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(glance.provider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("· \(window.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                UsageProgressBar(usage: window, now: now)
            }

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(window.percentUsed)%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
                Text(window.hasResetDate ? window.timeUntilReset(from: now) : "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private var accessibilityLabel: String {
        "\(glance.provider.displayName) \(window.displayName), "
            + "\(window.percentUsed) percent used, \(status.label), "
            + window.resetDescription(from: now)
    }
}

/// The sheet the accessory opens: the same detail the Providers tab pushes to.
struct UsageTabAccessoryDetail: View {
    let provider: Provider

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProviderSectionView(provider: provider)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif
