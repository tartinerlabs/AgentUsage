//
//  AboutTabView.swift
//  AgentUsage
//

#if os(macOS)
import SwiftUI

/// About content for the main window tab
struct AboutTabView: View {
    private let contentWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader

                aboutCard(title: "What \(Constants.appDisplayName) Tracks", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    VStack(alignment: .leading, spacing: 12) {
                        featureRow(
                            icon: "chart.bar.fill",
                            title: "Provider quota windows",
                            description: "Monitor Claude, Codex, and OpenCode usage pressure without opening provider dashboards."
                        )
                        Divider()
                        featureRow(
                            icon: "square.stack.3d.up.fill",
                            title: "Local token cost",
                            description: "Estimate token usage and spend from local coding-agent activity."
                        )
                        Divider()
                        featureRow(
                            icon: "bell.badge.fill",
                            title: "Usage alerts",
                            description: "Receive threshold notifications when quota pressure changes."
                        )
                    }
                }

                aboutCard(title: "Project", systemImage: "link") {
                    VStack(spacing: 12) {
                        linkRow(
                            icon: "curlybraces",
                            title: "GitHub Repository",
                            description: "View source code and documentation",
                            url: "https://github.com/tartinerlabs/AgentUsage"
                        )
                        Divider()
                        linkRow(
                            icon: "ladybug.fill",
                            title: "Report Issue",
                            description: "Found a bug or rough edge? Open an issue",
                            url: "https://github.com/tartinerlabs/AgentUsage/issues"
                        )
                        Divider()
                        linkRow(
                            icon: "star.fill",
                            title: "Star on GitHub",
                            description: "Follow development and releases",
                            url: "https://github.com/tartinerlabs/AgentUsage"
                        )
                    }
                }

                footer
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(Constants.appDisplayName)
                    .font(.title2.weight(.semibold))

                Text("Version \(Bundle.main.appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("A local-first usage monitor for AI coding tools.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Claude and its mark belong to Anthropic PBC. OpenAI, Codex, and the OpenAI mark belong to OpenAI. \(Constants.appDisplayName) is not affiliated with or endorsed by either provider.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("\u{00A9} 2025 Ru Chern Chong. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Constants.brandPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }

    private func linkRow(icon: String, title: String, description: String, url: String) -> some View {
        Group {
            if let destination = URL(string: url) {
                Link(destination: destination) {
                    linkRowContent(icon: icon, title: title, description: description)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func linkRowContent(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Constants.brandPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func aboutCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Constants.brandPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

#Preview {
    AboutTabView()
        .frame(width: 720, height: 560)
}
#endif
