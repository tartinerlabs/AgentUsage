//
//  ProviderSettingsCard.swift
//  AgentUsage
//

#if os(macOS)
import AgentUsageKit
import SwiftUI

/// One toggle per shipped provider. A provider turned off is not fetched, is
/// hidden on this Mac, and is no longer shared with iPhone and iPad.
struct ProviderSettingsCard: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        settingsCard(title: "Providers", systemImage: "switch.2") {
            VStack(spacing: 12) {
                Text(
                    "Turn off providers you don't use. \(Constants.appDisplayName) stops checking them, "
                        + "hides them on this Mac, and stops sharing them with iPhone and iPad. "
                        + "At least one provider stays on."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(ProviderSettings.shippedProviders) { provider in
                    Divider()

                    HStack {
                        Label(provider)
                            .font(.body)
                        Spacer()
                        Toggle("", isOn: binding(for: provider))
                            .tint(Constants.controlTint)
                            .labelsHidden()
                            .disabled(isLastEnabled(provider))
                            .accessibilityLabel(provider.displayName)
                            .help(helpText(for: provider))
                    }
                }
            }
        }
    }

    private func isLastEnabled(_ provider: Provider) -> Bool {
        viewModel.isProviderEnabled(provider) && !viewModel.canDisableProvider(provider)
    }

    private func helpText(for provider: Provider) -> String {
        isLastEnabled(provider)
            ? "At least one provider must stay on"
            : "Show \(provider.displayName) usage"
    }

    private func binding(for provider: Provider) -> Binding<Bool> {
        Binding(
            get: { viewModel.isProviderEnabled(provider) },
            set: { enabled in
                Task { await viewModel.setProviderEnabled(provider, enabled: enabled) }
            }
        )
    }
}
#endif
