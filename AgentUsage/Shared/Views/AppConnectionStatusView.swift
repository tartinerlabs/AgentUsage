//
//  AppConnectionStatusView.swift
//  AgentUsage
//

import SwiftUI

struct AppConnectionStatusView: View {
    let status: AppConnectionStatus
    let networkStatus: ContinuityNetworkStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            Divider()

            NetworkLinkDiagram(
                status: networkStatus,
                reduceMotion: reduceMotion
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.title)
        .accessibilityValue("\(status.detail) \(accessibilityConnectionSummary)")
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

    private var accessibilityConnectionSummary: String {
        [
            accessibilityDescription(label: "Mac", state: networkStatus.mac),
            accessibilityDescription(label: "iPhone", state: networkStatus.iPhone),
            accessibilityDescription(label: "iPad", state: networkStatus.iPad),
        ].joined(separator: " ")
    }

    private func accessibilityDescription(
        label: String,
        state: ContinuityNodeState
    ) -> String {
        switch state {
        case .connected:
            return "\(label) connected."
        case .waiting(let lastSeenAt):
            return lastSeenAt == nil
                ? "\(label) waiting."
                : "\(label) has not acknowledged the latest update."
        case .unavailable:
            return "\(label) not seen."
        case .checking:
            return "Checking \(label)."
        case .revoked:
            return "\(label) sync off."
        }
    }
}

private struct NetworkLinkDiagram: View {
    let status: ContinuityNetworkStatus
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 12) {
            deviceNode(
                systemImage: "laptopcomputer",
                label: "Mac",
                state: status.mac
            )

            AnimatedLinkLine(
                tint: linkState.tint,
                isActive: linkState.isActive,
                reduceMotion: reduceMotion
            )
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 18, maxHeight: 18)

            HStack(alignment: .top, spacing: 10) {
                deviceNode(
                    systemImage: "iphone",
                    label: "iPhone",
                    state: status.iPhone
                )
                deviceNode(
                    systemImage: "ipad",
                    label: "iPad",
                    state: status.iPad
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var linkState: ContinuityNodeState {
        if case .revoked = status.mac {
            return .revoked
        }
        if case .checking = status.mac {
            return .checking
        }
        if case .unavailable = status.mac {
            return .unavailable
        }

        let mobileStates = [status.iPhone, status.iPad]
        if mobileStates.contains(where: \.isConnected) {
            return .connected(lastSeenAt: nil)
        }
        if mobileStates.contains(where: \.isChecking) {
            return .checking
        }
        return .waiting(lastSeenAt: nil)
    }

    private func deviceNode(
        systemImage: String,
        label: String,
        state: ContinuityNodeState
    ) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.tint)
                    .frame(width: 34, height: 28)

                Image(systemName: state.statusImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 3, y: 2)
            }

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(state.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 54)
    }
}

private extension ContinuityNodeState {
    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .waiting, .revoked:
            return .orange
        case .unavailable, .checking:
            return .secondary
        }
    }

    var statusImage: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .waiting:
            return "clock.fill"
        case .unavailable:
            return "minus.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .revoked:
            return "link.badge.minus"
        }
    }

    var caption: String {
        switch self {
        case .connected(let lastSeenAt):
            return lastSeenAt.map { "Seen \(Self.relativeDescription(for: $0))" } ?? "Connected"
        case .waiting(let lastSeenAt):
            return lastSeenAt.map { "Seen \(Self.relativeDescription(for: $0))" } ?? "Waiting"
        case .unavailable:
            return "Not seen"
        case .checking:
            return "Checking"
        case .revoked:
            return "Off"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    private static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var isActive: Bool {
        isConnected || isChecking
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
                        packet(
                            progress: (progress + 0.5).truncatingRemainder(dividingBy: 1),
                            in: proxy.size
                        )
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
            .position(x: max(3, size.width * progress), y: size.height / 2)
    }

    private func animationProgress(at date: Date) -> Double {
        guard isActive, !reduceMotion else { return 0.5 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        AppConnectionStatusView(
            status: .linked(lastUpdatedText: "just now"),
            networkStatus: ContinuityNetworkStatus(
                mac: .connected(lastSeenAt: .now),
                iPhone: .connected(lastSeenAt: .now),
                iPad: .waiting(lastSeenAt: Date().addingTimeInterval(-3600))
            )
        )
        AppConnectionStatusView(
            status: .waitingForDevices(message: nil),
            networkStatus: ContinuityNetworkStatus(
                mac: .connected(lastSeenAt: .now),
                iPhone: .unavailable,
                iPad: .unavailable
            )
        )
    }
    .padding()
}
