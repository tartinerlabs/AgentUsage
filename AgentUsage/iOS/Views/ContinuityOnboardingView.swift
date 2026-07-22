//
//  ContinuityOnboardingView.swift
//  AgentUsage
//

#if os(iOS)
import SwiftUI

struct ContinuityOnboardingView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void

    @Environment(UsageViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var connectionState: ContinuityOnboardingMap.State = .idle
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 16)
                brandHeader
                introduction
                connectionMap
                actions
                privacyNote
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .task {
            await viewModel.initializeIfNeeded()
            updateFromCurrentConnectionState()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("AgentUsageMark")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(Circle())

            Text(Constants.appDisplayName)
                .font(.title.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            Text(connectionState == .connected ? "You’re connected" : "Your usage, wherever you are")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding.title")

            Text(introductionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Text(connectionState == .connected ? "Ready · Updated from your Mac" : "Companion setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(connectionState == .connected ? .green : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .animation(reduceMotion ? nil : .snappy, value: connectionState)
    }

    private var connectionMap: some View {
        VStack(spacing: 14) {
            ContinuityOnboardingMap(
                state: connectionState,
                highlightsMobileDevice: true
            )

            if let statusMessage {
                Label(
                    statusMessage,
                    systemImage: connectionState == .waiting
                        ? "clock.fill"
                        : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(connectionState == .waiting ? .orange : .green)
                .multilineTextAlignment(.center)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .smooth, value: statusMessage)
    }

    @ViewBuilder
    private var actions: some View {
        if connectionState == .connected {
            Button("Continue") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Constants.brandPrimary)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            Button {
                Task { await checkConnection() }
            } label: {
                HStack(spacing: 8) {
                    if connectionState == .connecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(connectionState == .waiting ? "Check Again" : "Check for Updates")
                }
                .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Constants.brandPrimary)
            .disabled(connectionState == .connecting)

            Button("Explore Without Data") {
                onSkip()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var privacyNote: some View {
        Label("Usage snapshots sync through your private iCloud database", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var introductionText: String {
        if connectionState == .connected {
            return "Your Mac shared the latest usage snapshot. AgentUsage will keep this device updated automatically."
        }
        return "AgentUsage for iPhone and iPad receives usage snapshots from AgentUsage on your Mac through iCloud."
    }

    private func checkConnection() async {
        statusMessage = nil
        connectionState = .connecting
        await viewModel.refreshContinuitySync()
        updateFromCurrentConnectionState()
    }

    private func updateFromCurrentConnectionState() {
        switch viewModel.appConnectionStatus {
        case .linked, .syncedFromMac:
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72)) {
                connectionState = .connected
                statusMessage = "Latest usage received from your Mac."
            }
        case .revoked:
            connectionState = .waiting
            statusMessage = "Continuity Sync is off. Resume it in Settings, then check again."
        default:
            connectionState = .waiting
            statusMessage = viewModel.appConnectionStatus.detail
        }
    }
}
#endif
