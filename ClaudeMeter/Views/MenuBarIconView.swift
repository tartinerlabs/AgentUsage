//
//  MenuBarIconView.swift
//  ClaudeMeter
//

import SwiftUI
import AppKit

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        if let nsImage = createColoredIcon() {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: "chart.bar.fill")
        }
    }

    private func createColoredIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(scale: .medium)
        guard let baseImage = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return nil
        }

        let tintColor = NSColor(viewModel.overallStatus.color)
        let coloredImage = NSImage(size: baseImage.size)

        coloredImage.lockFocus()
        tintColor.set()

        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        imageRect.fill()

        baseImage.draw(
            in: imageRect,
            from: .zero,
            operation: .destinationIn,
            fraction: 1.0
        )
        coloredImage.unlockFocus()

        coloredImage.isTemplate = false  // Prevents system tinting
        return coloredImage
    }
}
