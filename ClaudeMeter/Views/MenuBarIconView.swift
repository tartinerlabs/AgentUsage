//
//  MenuBarIconView.swift
//  ClaudeMeter
//

#if os(macOS)
import SwiftUI
import AppKit
import ClaudeMeterKit
internal import Combine

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel
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
        Image(nsImage: renderMenuBarImage())
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                if windowAtLimit != nil {
                    now = date
                }
            }
    }

    private func renderMenuBarImage() -> NSImage {
        let content = menuBarContent

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let cgImage = renderer.cgImage else {
            return NSImage(size: NSSize(width: 50, height: 22))
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width) / renderer.scale,
            height: CGFloat(cgImage.height) / renderer.scale
        ))
        image.isTemplate = false

        return image
    }

    private var menuBarContent: some View {
        HStack(spacing: 6) {
            if let snapshot = viewModel.snapshot {
                if viewModel.menuBarShowSession {
                    usageColumn(label: "CURR", value: snapshot.session.utilization)
                }
                if viewModel.menuBarShowAllModels {
                    usageColumn(label: "ALL", value: snapshot.opus.utilization)
                }
                if viewModel.menuBarShowSonnet, let sonnet = snapshot.sonnet {
                    usageColumn(label: "SONNET", value: sonnet.utilization)
                }

                // Fallback if nothing is enabled
                if !viewModel.menuBarShowSession && !viewModel.menuBarShowAllModels && !viewModel.menuBarShowSonnet {
                    usageColumn(label: "CURR", value: snapshot.session.utilization)
                }
            } else {
                Text("--%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if let window = windowAtLimit {
                Text(window.timeUntilReset(from: now))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }
        }
    }

    @ViewBuilder
    private func usageColumn(label: String, value: Double) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8 ))
                .foregroundStyle(.white)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10 ))
                .foregroundStyle(.white)
        }
    }
}
#endif

