//
//  AppConnectionStatusView.swift
//  AgentUsage
//

import SwiftUI

struct AppConnectionStatusView: View {
    let status: AppConnectionStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            Divider()

            NetworkLinkDiagram(
                tint: status.tint,
                isActive: isLinkActive,
                reduceMotion: reduceMotion
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.title)
        .accessibilityValue(status.detail)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.body)
                    .foregroundStyle(status.tint)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if status.isInProgress {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
        }
    }

    private var isLinkActive: Bool {
        switch status {
        case .linked, .syncedFromMac, .checking:
            return true
        case .waitingForMac, .revoked, .needsSetup:
            return false
        }
    }
}

private struct NetworkLinkDiagram: View {
    let tint: Color
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 12) {
            deviceNode(systemImage: "laptopcomputer", label: "Mac")

            AnimatedLinkLine(
                tint: tint,
                isActive: isActive,
                reduceMotion: reduceMotion
            )
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 18, maxHeight: 18)

            HStack(spacing: 10) {
                deviceNode(systemImage: "iphone", label: "iPhone")
                deviceNode(systemImage: "ipad", label: "iPad")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func deviceNode(systemImage: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 34, height: 28)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 48)
    }
}

private struct AnimatedLinkLine: View {
    let tint: Color
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let progress = animationProgress(at: timeline.date)

                ZStack {
                    Capsule()
                        .fill(tint.opacity(isActive ? 0.22 : 0.14))
                        .frame(width: proxy.size.width, height: 3)

                    if isActive {
                        packet(progress: progress, in: proxy.size)
                        packet(progress: (progress + 0.5).truncatingRemainder(dividingBy: 1), in: proxy.size)
                    } else {
                        Circle()
                            .fill(tint.opacity(0.38))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func packet(progress: Double, in size: CGSize) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .shadow(color: tint.opacity(0.35), radius: 3)
            .position(x: max(3, size.width * progress), y: size.height / 2)
    }

    private func animationProgress(at date: Date) -> Double {
        guard isActive, !reduceMotion else { return 0.5 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        AppConnectionStatusView(status: .linked(lastUpdatedText: "2 minutes ago"))
        AppConnectionStatusView(status: .syncedFromMac(lastUpdatedText: "just now"))
        AppConnectionStatusView(status: .waitingForMac)
    }
    .padding()
}
