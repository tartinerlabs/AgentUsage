//
//  AboutView.swift
//  ClaudeMeter
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            // App Name and Version
            VStack(spacing: 4) {
                Text("ClaudeMeter")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(Bundle.main.appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("Monitor your Claude API usage directly from the menu bar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Divider()
                .padding(.horizontal, 40)

            // Links
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/tartinerlabs/ClaudeMeter/issues")!) {
                    Label("Report Issue", systemImage: "ladybug")
                }
            }
            .buttonStyle(.link)

            Spacer()

            // Copyright
            Text("\u{00A9} 2025 Ru Chern Chong. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 320, height: 340)
    }
}

#Preview {
    AboutView()
}
