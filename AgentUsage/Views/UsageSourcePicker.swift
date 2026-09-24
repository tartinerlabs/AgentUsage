//
//  UsageSourcePicker.swift
//  AgentUsage
//

import SwiftUI
import AgentUsageKit

/// Chooses whose local token and cost usage the provider cards show: every Mac
/// combined, or one Mac on its own. Quota windows are account-wide and do not
/// change with this choice. Hidden by callers until there are two or more Macs.
struct UsageSourcePicker: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        Picker(selection: selection) {
            ForEach(viewModel.usageSourceOptions) { option in
                Text(option.title).tag(option.selection)
            }
        } label: {
            Label("Usage from", systemImage: "desktopcomputer")
        }
        .pickerStyle(.menu)
        .accessibilityHint("Chooses which Mac's token and cost usage to show")
    }

    /// Reads the effective source so a Mac that stopped publishing never leaves
    /// the picker pointing at a missing tag.
    private var selection: Binding<UsageSourceSelection> {
        Binding(
            get: { viewModel.effectiveUsageSource },
            set: { viewModel.usageSource = $0 }
        )
    }
}
