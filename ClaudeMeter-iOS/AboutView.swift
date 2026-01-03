//
//  AboutView.swift
//  ClaudeMeter-iOS
//

import SwiftUI

/// iOS About view
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon
                if let icon = Bundle.main.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }

                // App Name and Version
                VStack(spacing: 4) {
                    Text("ClaudeMeter")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Description
                Text("Monitor your Claude API usage directly from your device.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal, 40)

                // Links
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter")!) {
                        HStack {
                            Label("GitHub", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                        )
                    }

                    Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter/issues")!) {
                        HStack {
                            Label("Report Issue", systemImage: "ladybug")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                        )
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)

                // Copyright
                Text("\u{00A9} 2025 Ru Chern Chong. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

extension Bundle {
    var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
