//
//  AppBuildBadge.swift
//  AgentUsage
//

import AgentUsageKit
import SwiftUI

extension Bundle {
    /// `MARKETING_VERSION` from `Config/Version.xcconfig`, e.g. "0.33.0".
    var marketingVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// `CURRENT_PROJECT_VERSION` from `Config/Version.xcconfig`, e.g. "83".
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Version with build, e.g. "0.33.0 (83)".
    var appVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}

/// Neutral pill showing the build number, styled like the provider plan badge.
struct AppBuildBadge: View {
    var body: some View {
        Text("Build \(Bundle.main.buildNumber)")
            .font(.caption.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(AgentUsageColors.usageProgress)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AgentUsageColors.usageProgress.opacity(0.12))
            )
    }
}

#Preview {
    AppBuildBadge()
        .padding()
}
