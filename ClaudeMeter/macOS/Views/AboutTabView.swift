//
//  AboutTabView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI

/// About content for the main window tab
struct AboutTabView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

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
                .frame(maxWidth: 300)

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
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutTabView()
        .frame(width: 500, height: 400)
}
#endif
