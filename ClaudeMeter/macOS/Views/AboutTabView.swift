//
//  AboutTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// About content for the main window tab
struct AboutTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // App Header
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ClaudeMeter")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Version \(Bundle.main.appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Monitor your Claude API usage directly from the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Features Section
                aboutCard(title: "Features") {
                    VStack(alignment: .leading, spacing: 12) {
                        featureRow(
                            icon: "chart.bar.fill",
                            title: "Usage Tracking",
                            description: "Monitor session, Opus, and Sonnet usage limits"
                        )
                        Divider()
                        featureRow(
                            icon: "dollarsign.circle.fill",
                            title: "Cost Analysis",
                            description: "Track token usage and estimated costs"
                        )
                        Divider()
                        featureRow(
                            icon: "menubar.rectangle",
                            title: "Menu Bar App",
                            description: "Quick access from your menu bar"
                        )
                        Divider()
                        featureRow(
                            icon: "arrow.clockwise",
                            title: "Auto Refresh",
                            description: "Automatic updates at configurable intervals"
                        )
                    }
                }

                // Links Section
                aboutCard(title: "Links") {
                    VStack(spacing: 12) {
                        linkRow(
                            icon: "link",
                            title: "GitHub Repository",
                            description: "View source code and documentation",
                            url: "https://github.com/tartinerlabs/ClaudeMeter"
                        )
                        Divider()
                        linkRow(
                            icon: "ladybug.fill",
                            title: "Report Issue",
                            description: "Found a bug? Let us know",
                            url: "https://github.com/tartinerlabs/ClaudeMeter/issues"
                        )
                        Divider()
                        linkRow(
                            icon: "star.fill",
                            title: "Star on GitHub",
                            description: "Show your support",
                            url: "https://github.com/tartinerlabs/ClaudeMeter"
                        )
                    }
                }

                Spacer(minLength: 0)

                // Copyright
                Text("\u{00A9} 2025 Ru Chern Chong. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Constants.brandPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func linkRow(icon: String, title: String, description: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func aboutCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
}

#Preview {
    AboutTabView()
        .frame(width: 500, height: 400)
}
#endif
