//
//  DashboardView.swift
//  AgentUsage
//

#if os(iOS)
import AgentUsageKit
import Combine
import SwiftUI
import UIKit

/// Main iOS dashboard showing every available provider in one linear card stack.
struct DashboardView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isOffline || viewModel.isUsingCachedData {
                    offlineIndicator
                }

                let providerSnapshots = viewModel.availableProviderSnapshots
                if providerSnapshots.isEmpty {
                    dashboardState
                } else {
                    providerCards(providerSnapshots)
                }

                LiveActivityControlCard(
                    manager: viewModel.liveActivityManager,
                    snapshots: providerSnapshots,
                    now: now
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .navigationTitle(Constants.appDisplayName)
        .task {
            await viewModel.initializeIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    // MARK: - Provider Cards

    private func providerCards(_ snapshots: [ProviderUsageSnapshot]) -> some View {
        ForEach(snapshots) { snapshot in
            ProviderCardView(
                provider: snapshot.provider,
                planName: snapshot.planName,
                windows: snapshot.windows,
                extraUsage: snapshot.extraUsage,
                now: now,
                showExtraUsage: viewModel.showExtraUsageIndicators,
                isServiceDown: viewModel.isServiceDown(snapshot.provider),
                rateLimitResetCredits: snapshot.rateLimitResetCredits
            )
            .accessibilityLabel("\(snapshot.provider.displayName) usage")
        }
    }

    // MARK: - Offline Indicator

    private var offlineIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isOffline ? "wifi.slash" : "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isOffline ? "Offline Mode" : "Using Cached Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let lastUpdate = viewModel.timeSinceLastUpdate {
                    Text("Last updated \(lastUpdate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.isOffline ? "Offline mode" : "Using cached data")
        .accessibilityValue(viewModel.timeSinceLastUpdate.map { "Last updated \($0)" } ?? "")
    }

    // MARK: - Provider-neutral States

    @ViewBuilder
    private var dashboardState: some View {
        if viewModel.isNoUsageData {
            noUsageDataView
        } else if viewModel.isLoading || viewModel.isRefreshingContinuitySync {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            waitingView
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Unable to Load Usage")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await viewModel.refresh(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Constants.brandPrimary)
            .accessibilityHint("Attempts to reload usage data")
        }
        .stateCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error loading usage")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading usage data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading usage data")
    }

    private var noUsageDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No usage data")
                .font(.headline)
            Text("Usage limits will appear when a connected provider reports a new window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No usage data yet")
        .accessibilityHint("Usage limits will appear when a connected provider reports a new window")
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.largeTitle)
                .foregroundStyle(Constants.brandPrimary)
                .accessibilityHidden(true)
            Text("Waiting for usage")
                .font(.headline)
            Text("Open Agent Usage on your Mac to share the latest provider snapshots through iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Check Again") {
                    Task { await viewModel.refreshContinuitySync() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Constants.brandPrimary)

                Button("Setup Guide") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .stateCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for usage from your Mac")
        .accessibilityHint("Open the setup guide or check for updates again")
    }
}

private struct LiveActivityControlCard: View {
    @ObservedObject var manager: LiveActivityManager

    let snapshots: [ProviderUsageSnapshot]
    let now: Date

    @Environment(\.openURL) private var openURL
    @State private var draftProvider: Provider?
    @State private var draftWindowID: UsageWindowID?
    @State private var isPerformingAction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !manager.activitiesEnabled {
                disabledState
            } else if eligibleSnapshots.isEmpty {
                unavailableState
            } else {
                selectionControls
                activityControls
            }

            if let startError = manager.startError {
                Label(startError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Live Activity could not start: \(startError)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Activity controls")
        .task(id: selectionSignature) {
            reconcileDraftSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(Constants.brandPrimary)
            Text("Live Activity")
                .font(.headline)
            Spacer()
            if manager.isRunning {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            }
        }
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Live Activities are turned off", systemImage: "exclamationmark.circle")
                .font(.subheadline)
            Text("Enable Live Activities in Settings to keep one provider window visible on the Lock Screen and Dynamic Island.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if manager.isRunning {
                activeTrackingSummary
            }

            HStack(spacing: 10) {
                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(Constants.brandPrimary)

                if manager.isRunning {
                    stopButton
                }
            }
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No current windows available", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline)
            Text("A Live Activity can start when a provider reports a usage window that has not reset.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if manager.isRunning {
                activeTrackingSummary
                stopButton
            }
        }
    }

    private var selectionControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Provider")
                    .font(.subheadline)
                Spacer()
                Picker("Provider", selection: $draftProvider) {
                    ForEach(eligibleSnapshots) { snapshot in
                        Text(snapshot.provider.displayName)
                            .tag(Optional(snapshot.provider))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(eligibleSnapshots.count == 1 || isPerformingAction)
                .onChange(of: draftProvider) { _, provider in
                    guard let provider else {
                        draftWindowID = nil
                        return
                    }
                    draftWindowID = eligibleWindows(for: provider).first?.windowID
                }
            }

            Divider()

            HStack {
                Text("Window")
                    .font(.subheadline)
                Spacer()
                Picker("Window", selection: $draftWindowID) {
                    ForEach(selectedProviderWindows, id: \.windowID) { window in
                        Text(window.displayName)
                            .tag(Optional(window.windowID))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(selectedProviderWindows.count == 1 || isPerformingAction)
            }
        }
    }

    @ViewBuilder
    private var activityControls: some View {
        if manager.isRunning {
            activeTrackingSummary

            if activeSelectionMatchesDraft {
                stopButton
            } else {
                HStack(spacing: 10) {
                    Button {
                        activateDraftSelection()
                    } label: {
                        actionLabel("Switch Live Activity")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Constants.brandPrimary)
                    .disabled(draftSelection == nil || isPerformingAction)

                    stopButton
                }
            }
        } else {
            Text("Keep one current provider window visible on the Lock Screen and Dynamic Island.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                activateDraftSelection()
            } label: {
                actionLabel("Start Live Activity")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Constants.brandPrimary)
            .disabled(draftSelection == nil || isPerformingAction)
        }
    }

    private var activeTrackingSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "wave.3.right")
                .foregroundStyle(.green)
            Text(activeTrackingText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stopButton: some View {
        Button {
            isPerformingAction = true
            Task {
                await manager.stop()
                isPerformingAction = false
            }
        } label: {
            actionLabel("Stop")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(isPerformingAction)
        .accessibilityLabel("Stop Live Activity")
    }

    @ViewBuilder
    private func actionLabel(_ title: String) -> some View {
        if isPerformingAction {
            ProgressView()
        } else {
            Text(title)
        }
    }

    private var eligibleSnapshots: [ProviderUsageSnapshot] {
        snapshots.filter { !eligibleWindows(in: $0).isEmpty }
    }

    private var selectedProviderWindows: [UsageWindow] {
        guard let draftProvider else { return [] }
        return eligibleWindows(for: draftProvider)
    }

    private func eligibleWindows(for provider: Provider) -> [UsageWindow] {
        guard let snapshot = snapshots.first(where: { $0.provider == provider }) else { return [] }
        return eligibleWindows(in: snapshot)
    }

    private func eligibleWindows(in snapshot: ProviderUsageSnapshot) -> [UsageWindow] {
        snapshot.windows.filter { !$0.isExpired(from: now) }
    }

    private var draftSelection: UsageActivitySelection? {
        guard
            let draftProvider,
            let draftWindowID,
            eligibleWindows(for: draftProvider).contains(where: { $0.windowID == draftWindowID })
        else { return nil }

        return UsageActivitySelection(provider: draftProvider, windowID: draftWindowID)
    }

    private var activeSelectionMatchesDraft: Bool {
        manager.activeSelection == draftSelection
    }

    private var activeTrackingText: String {
        guard let selection = manager.activeSelection else {
            if let windowName = manager.activeWindowDisplayName {
                return "Tracking Claude · \(windowName)"
            }
            return "Tracking usage"
        }
        let windowName = manager.activeWindowDisplayName ?? selection.windowID.rawValue
        return "Tracking \(selection.provider.displayName) · \(windowName)"
    }

    private var selectionSignature: String {
        let choices = eligibleSnapshots.flatMap { snapshot in
            eligibleWindows(in: snapshot).map { window in
                "\(snapshot.provider.rawValue):\(window.windowID.rawValue):\(window.resetsAt.timeIntervalSince1970)"
            }
        }
        let active = manager.activeSelection.map {
            "active:\($0.provider.rawValue):\($0.windowID.rawValue)"
        } ?? "inactive"
        return (choices + [active]).joined(separator: "|")
    }

    private func reconcileDraftSelection() {
        if let draftSelection, contains(draftSelection) {
            return
        }
        if let activeSelection = manager.activeSelection, contains(activeSelection) {
            draftProvider = activeSelection.provider
            draftWindowID = activeSelection.windowID
            return
        }
        draftProvider = eligibleSnapshots.first?.provider
        draftWindowID = eligibleSnapshots.first.flatMap { eligibleWindows(in: $0).first?.windowID }
    }

    private func contains(_ selection: UsageActivitySelection) -> Bool {
        eligibleWindows(for: selection.provider).contains { $0.windowID == selection.windowID }
    }

    private func activateDraftSelection() {
        guard let selection = draftSelection else { return }
        isPerformingAction = true
        Task {
            await manager.activate(selection: selection, from: snapshots)
            isPerformingAction = false
        }
    }
}

private extension View {
    func stateCard() -> some View {
        padding(40)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environment(UsageViewModel(
                credentialProvider: iOSCredentialService()
            ))
    }
}
#endif
