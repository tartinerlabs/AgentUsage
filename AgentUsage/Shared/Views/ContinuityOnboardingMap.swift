//
//  ContinuityOnboardingMap.swift
//  AgentUsage
//

import SwiftUI

struct ContinuityOnboardingMap: View {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case waiting
    }

    let state: State
    let highlightsMobileDevice: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsePosition: CGFloat = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalMap
            compactMap
        }
        .task(id: state) {
            updatePulseAnimation()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Continuity Sync connection")
        .accessibilityValue(accessibilityValue)
    }

    private var horizontalMap: some View {
        HStack(spacing: 18) {
            deviceNode(
                icon: "laptopcomputer",
                title: "This Mac",
                subtitle: highlightsMobileDevice ? "Data source" : sourceSubtitle,
                isHighlighted: !highlightsMobileDevice
            )

            connectionLine
                .frame(minWidth: 90, maxWidth: .infinity)

            deviceNode(
                icon: "icloud",
                title: "Private iCloud",
                subtitle: cloudSubtitle,
                isHighlighted: state == .connecting
            )

            connectionLine
                .frame(minWidth: 90, maxWidth: .infinity)

            deviceNode(
                icon: "iphone.and.arrow.forward.inward",
                title: "iPhone & iPad",
                subtitle: mobileSubtitle,
                isHighlighted: highlightsMobileDevice || state == .connected
            )
        }
    }

    private var compactMap: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "laptopcomputer")
                connectionLine.frame(width: 64)
                Image(systemName: "icloud")
                connectionLine.frame(width: 64)
                Image(systemName: "iphone.and.arrow.forward.inward")
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(Constants.iconPacificBlue)

            Text(compactStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func deviceNode(
        icon: String,
        title: String,
        subtitle: String,
        isHighlighted: Bool
    ) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(isHighlighted ? Constants.iconPacificBlue.opacity(0.12) : Color.secondary.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHighlighted ? Constants.iconPacificBlue : .secondary)
                    .frame(width: 88, height: 88)
                    .symbolEffect(.pulse, isActive: state == .connecting && isHighlighted && !reduceMotion)

                if state == .connected && isHighlighted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                        .background(.background, in: Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 120)
    }

    private var connectionLine: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 2)

                Capsule()
                    .fill(Constants.iconPacificBlue.opacity(state == .idle ? 0.35 : 0.8))
                    .frame(
                        width: state == .connected
                            ? geometry.size.width
                            : max(8, geometry.size.width * pulsePosition),
                        height: 2
                    )

                if state == .connecting {
                    Circle()
                        .fill(Constants.iconPacificBlue)
                        .frame(width: 10, height: 10)
                        .shadow(color: Constants.iconPacificBlue.opacity(0.45), radius: 6)
                        .offset(x: max(0, (geometry.size.width - 10) * pulsePosition))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
    }

    private var sourceSubtitle: String {
        state == .connected ? "Connected" : "Data source"
    }

    private var cloudSubtitle: String {
        switch state {
        case .connecting: "Checking"
        case .connected: "Available"
        case .waiting: "Waiting"
        case .idle: "Private database"
        }
    }

    private var mobileSubtitle: String {
        switch state {
        case .connected: "Up to date"
        case .connecting: "Checking"
        case .waiting: "Waiting for Mac"
        case .idle: "Companion devices"
        }
    }

    private var compactStatus: String {
        switch state {
        case .idle: "This Mac privately shares usage snapshots through iCloud."
        case .connecting: "Checking the connection…"
        case .connected: "Your devices are connected."
        case .waiting: "Waiting for the latest update from your Mac."
        }
    }

    private var accessibilityValue: String {
        compactStatus
    }

    private func updatePulseAnimation() {
        pulsePosition = state == .connected ? 1 : 0
        guard state == .connecting else { return }

        if reduceMotion {
            pulsePosition = 0.55
        } else {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) {
                pulsePosition = 1
            }
        }
    }
}

private extension Constants {
    static let iconPacificBlue = Color(red: 113 / 255, green: 151 / 255, blue: 212 / 255)
}
