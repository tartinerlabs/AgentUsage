//
//  MenuBarIconView.swift
//  ClaudeMeter
//

import SwiftUI
import ClaudeMeterKit
import AppKit
internal import Combine

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController
    @State private var now = Date()

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
            if let nsImage = createColoredIcon(showBadge: updaterController.updateAvailable) {
                Image(nsImage: nsImage)
            } else {
                Image(systemName: "chart.bar.fill")
            }

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

    private func createColoredIcon(showBadge: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(scale: .medium)
        guard let baseImage = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return nil
        }

        let tintColor = NSColor(viewModel.overallStatus.color)

        // Add padding for badge if needed
        let badgeSize: CGFloat = 6
        let padding: CGFloat = showBadge ? badgeSize / 2 : 0
        let finalSize = NSSize(
            width: baseImage.size.width + padding,
            height: baseImage.size.height + padding
        )

        let coloredImage = NSImage(size: finalSize)

        coloredImage.lockFocus()

        // Draw the base icon
        tintColor.set()
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        imageRect.fill()

        baseImage.draw(
            in: imageRect,
            from: .zero,
            operation: .destinationIn,
            fraction: 1.0
        )

        // Draw badge dot if update available
        if showBadge {
            let badgeColor = NSColor.systemOrange
            badgeColor.setFill()

            let badgeRect = NSRect(
                x: baseImage.size.width - badgeSize / 2,
                y: baseImage.size.height - badgeSize / 2,
                width: badgeSize,
                height: badgeSize
            )
            NSBezierPath(ovalIn: badgeRect).fill()
        }

        coloredImage.unlockFocus()

        coloredImage.isTemplate = false  // Prevents system tinting
        return coloredImage
    }
}
