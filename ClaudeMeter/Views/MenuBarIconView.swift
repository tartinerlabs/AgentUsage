//
//  MenuBarIconView.swift
//  ClaudeMeter
//

import SwiftUI
import ClaudeMeterKit
internal import Combine

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @State private var now = Date()

    /// Build the percentage display text based on enabled windows
    private var percentageText: String {
        guard let snapshot = viewModel.snapshot else { return "--%" }

        var parts: [String] = []

        if viewModel.menuBarShowSession {
            parts.append("\(snapshot.session.utilization)%")
        }
        if viewModel.menuBarShowAllModels {
            parts.append("\(snapshot.opus.utilization)%")
        }
        if viewModel.menuBarShowSonnet, let sonnet = snapshot.sonnet {
            parts.append("\(sonnet.utilization)%")
        }

        // If nothing is enabled, show session by default
        if parts.isEmpty {
            parts.append("\(snapshot.session.utilization)%")
        }

        return parts.joined(separator: " ")
    }

    /// Find the window at 100% with the soonest reset time (or any window if debug simulation is on)
    private var windowAtLimit: UsageWindow? {
        guard let snapshot = viewModel.snapshot else { return nil }

        #if DEBUG
        // In debug mode, show countdown for any window if simulation is enabled
        if viewModel.debugSimulate100Percent {
            let windows = [snapshot.session, snapshot.opus, snapshot.sonnet].compactMap { $0 }
            return windows.min(by: { $0.resetsAt < $1.resetsAt })
        }
        #endif

        let windows = [snapshot.session, snapshot.opus, snapshot.sonnet]
            .compactMap { $0 }
            .filter { $0.isAtLimit }
        return windows.min(by: { $0.resetsAt < $1.resetsAt })
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(percentageText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            if let window = windowAtLimit {
                Text(window.timeUntilReset(from: now))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            if windowAtLimit != nil {
                now = date
            }
        }
    }
}
