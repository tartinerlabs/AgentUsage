//
//  GeneralSettingsCard.swift
//  AgentUsage
//

#if os(macOS)
import AgentUsageKit
import SwiftUI

struct GeneralSettingsCard: View {
    @Environment(UsageViewModel.self) private var viewModel
    @StateObject private var launchAtLogin = LaunchAtLoginService.shared

    var body: some View {
        @Bindable var viewModel = viewModel

        settingsCard(title: "General", systemImage: "gearshape") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Automatically start \(Constants.appDisplayName) when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $launchAtLogin.isEnabled)
                        .labelsHidden()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup Guide")
                            .font(.body)
                        Text("Review local data access and Continuity Sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Setup Again") {
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Refresh Interval")
                            .font(.body)
                        Text("How often to fetch usage data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $viewModel.refreshInterval) {
                        ForEach(RefreshFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu Bar Display")
                        .font(.body)
                    Text("Pin up to two quota windows per provider. Providers without live pinned data take no space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.menuBarProviders) { provider in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(provider.displayName, systemImage: provider.iconName)
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text("\(viewModel.menuBarPinnedWindows(for: provider).count)/\(MenuBarSettingsManager.maximumPinsPerProvider)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }

                                ForEach(
                                    viewModel.menuBarSupportedWindows(for: provider),
                                    id: \.rawValue
                                ) { window in
                                    let isPinned = viewModel.isMenuBarWindowPinned(
                                        window,
                                        for: provider
                                    )
                                    Toggle(
                                        window.displayName,
                                        isOn: menuBarPinBinding(window, provider: provider)
                                    )
                                    .disabled(
                                        !isPinned
                                            && !viewModel.canPinMenuBarWindow(
                                                window,
                                                for: provider
                                            )
                                    )
                                }
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Usage Indicators")
                            .font(.body)
                        Text("Show extra usage badges, bars, and cost sections when a provider reports on-demand spend.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.showExtraUsageIndicators)
                        .labelsHidden()
                }
            }
        }
    }

    private func menuBarPinBinding(
        _ window: UsageWindowType,
        provider: Provider
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.isMenuBarWindowPinned(window, for: provider) },
            set: { viewModel.setMenuBarWindowPinned(window, for: provider, isPinned: $0) }
        )
    }
}
#endif
