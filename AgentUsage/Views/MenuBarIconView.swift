//
//  MenuBarIconView.swift
//  AgentUsage
//

#if os(macOS)
import AppKit
import AgentUsageKit
import OSLog
import SwiftUI

struct MenuBarStatusContent: Equatable {
    struct Metric: Equatable, Identifiable {
        let id: String
        let label: String
        let percentUsed: Int

        var value: String { "\(percentUsed)%" }
    }

    struct Group: Equatable, Identifiable {
        let id: String
        let displayName: String
        let metrics: [Metric]
    }

    let groups: [Group]

    var isEmpty: Bool { groups.isEmpty }

    var accessibilityText: String {
        groups.map { group in
            let metrics = group.metrics.map {
                "\($0.label) \($0.percentUsed) percent used"
            }
            .joined(separator: ", ")
            return "\(group.displayName), \(metrics)"
        }
        .joined(separator: "; ")
    }
}

enum MenuBarStatusContentBuilder {
    private static let providerOrder: [Provider] = [.claude, .codex]

    static func build(
        snapshots: [Provider: ProviderUsageSnapshot],
        pinnedWindows: [Provider: [UsageWindowType]],
        now: Date = Date()
    ) -> MenuBarStatusContent {
        let groups = providerOrder.compactMap { provider -> MenuBarStatusContent.Group? in
            guard let snapshot = snapshots[provider] else { return nil }

            let metrics = (pinnedWindows[provider] ?? [])
                .prefix(MenuBarSettingsManager.maximumPinsPerProvider)
                .compactMap { windowType -> MenuBarStatusContent.Metric? in
                    guard let window = snapshot.windows.first(where: {
                        $0.windowID.rawValue == windowType.rawValue && !$0.isExpired(from: now)
                    }),
                    window.utilization.isFinite,
                    window.utilization >= Double(Int.min),
                    window.utilization <= Double(Int.max) else { return nil }

                    return MenuBarStatusContent.Metric(
                        id: windowType.rawValue,
                        label: windowType.displayName,
                        percentUsed: Int(window.utilization.rounded())
                    )
                }

            guard !metrics.isEmpty else { return nil }
            return MenuBarStatusContent.Group(
                id: provider.rawValue,
                displayName: provider.displayName,
                metrics: metrics
            )
        }

        return MenuBarStatusContent(groups: groups)
    }
}

@MainActor
enum MenuBarStatusRenderer {
    private static var lastRender: (
        content: MenuBarStatusContent,
        scale: CGFloat,
        image: NSImage?
    )?

    static func image(
        for content: MenuBarStatusContent,
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) -> NSImage? {
        guard !content.isEmpty else { return nil }
        if let lastRender,
           lastRender.content == content,
           lastRender.scale == scale {
            return lastRender.image
        }

        let renderer = ImageRenderer(content: MenuBarStatusStrip(content: content))
        renderer.scale = scale

        let image: NSImage?
        if let rendered = renderer.cgImage {
            let cropped = trimmedToVisibleContent(rendered) ?? rendered
            let renderedImage = NSImage(
                cgImage: cropped,
                size: NSSize(
                    width: CGFloat(cropped.width) / scale,
                    height: CGFloat(cropped.height) / scale
                )
            )
            renderedImage.isTemplate = true
            renderedImage.accessibilityDescription = content.accessibilityText
            image = renderedImage
        } else {
            Logger.viewModel.warning("Failed to render compact menu bar status")
            image = nil
        }

        lastRender = (content, scale, image)
        return image
    }

    static let fallbackImage: NSImage = {
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: Constants.appDisplayName
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }()

    private static func trimmedToVisibleContent(_ image: CGImage) -> CGImage? {
        guard let bounds = visibleBounds(of: image) else { return nil }
        return image.cropping(to: bounds)
    }

    private static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var alpha = [UInt8](repeating: 0, count: width * height)
        let didDraw = alpha.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] != 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}

struct MenuBarIconView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        let content = statusContent
        let image = MenuBarStatusRenderer.image(for: content)
            ?? MenuBarStatusRenderer.fallbackImage

        Image(nsImage: image)
            .accessibilityLabel(content.isEmpty ? Constants.appDisplayName : content.accessibilityText)
            .task {
                await viewModel.initializeIfNeeded()
            }
    }

    private var statusContent: MenuBarStatusContent {
        var snapshots: [Provider: ProviderUsageSnapshot] = [:]
        var pinnedWindows: [Provider: [UsageWindowType]] = [:]

        for provider in viewModel.menuBarProviders {
            snapshots[provider] = viewModel.usageSnapshot(for: provider)
            pinnedWindows[provider] = viewModel.menuBarPinnedWindows(for: provider)
        }

        return MenuBarStatusContentBuilder.build(
            snapshots: snapshots,
            pinnedWindows: pinnedWindows
        )
    }
}

private struct MenuBarStatusStrip: View {
    let content: MenuBarStatusContent

    var body: some View {
        HStack(spacing: 11) {
            ForEach(content.groups) { group in
                HStack(spacing: 4) {
                    MenuBarProviderMark(providerID: group.id)
                    metricValues(group.metrics)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .fixedSize()
    }

    @ViewBuilder
    private func metricValues(_ metrics: [MenuBarStatusContent.Metric]) -> some View {
        if metrics.count == 1 {
            Text(metrics[0].value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
        } else {
            VStack(alignment: .trailing, spacing: -2) {
                ForEach(metrics) { metric in
                    Text(metric.value)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .fixedSize()
        }
    }
}

private struct MenuBarProviderMark: View {
    let providerID: String

    private var assetName: String? {
        switch providerID {
        case Provider.claude.rawValue: "ClaudeProviderMark"
        case Provider.codex.rawValue: "CodexProviderMark"
        default: nil
        }
    }

    private var fallbackSymbol: String {
        switch providerID {
        case Provider.claude.rawValue: Provider.claude.iconName
        case Provider.codex.rawValue: Provider.codex.iconName
        default: "gauge.medium"
        }
    }

    var body: some View {
        Group {
            if let assetName,
               let image = NSImage(named: NSImage.Name(assetName)) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
#endif
