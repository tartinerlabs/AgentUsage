//
//  MenuBarIconView.swift
//  ClaudeMeter
//

import SwiftUI
import AppKit

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @EnvironmentObject private var updaterController: UpdaterController

    var body: some View {
        if let nsImage = createColoredIcon(showBadge: updaterController.updateAvailable) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: "chart.bar.fill")
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
