//
//  NotificationSettingsCard.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI

struct NotificationSettingsCard: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var notificationSettings = NotificationSettings.load()

    var body: some View {
        settingsCard(title: "Notifications", systemImage: "bell.badge") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Usage Alerts")
                            .font(.body)
                        Text("Notify when usage crosses 25%, 50%, 75%, or 100%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: notificationsEnabledBinding)
                        .labelsHidden()
                }

                if viewModel.notificationsEnabled {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Extra Usage Alert")
                                .font(.body)
                            Text("Notify when extra usage starts (plan limit exceeded). Requires extra usage to be enabled in your provider account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { notificationSettings.notifyExtraUsage },
                            set: {
                                notificationSettings.notifyExtraUsage = $0
                                notificationSettings.save()
                            }
                        ))
                        .labelsHidden()
                    }

                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test Notification")
                            .font(.body)
                        Text("Uses synthetic content and does not require usage data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Test") {
                        Task { await viewModel.sendTestNotification() }
                    }
                }

                notificationTestStatus
            }
        }
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.notificationsEnabled },
            set: { enabled in
                Task { await viewModel.setNotificationsEnabled(enabled) }
            }
        )
    }

    @ViewBuilder
    private var notificationTestStatus: some View {
        switch viewModel.notificationTestResult {
        case .some(.sent):
            EmptyView()
        case .some(.permissionDenied):
            Label("Notifications are disabled in System Settings.", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        case .some(.failed(let message)):
            Label("Could not send the test: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .none:
            EmptyView()
        }
    }
}
#endif
