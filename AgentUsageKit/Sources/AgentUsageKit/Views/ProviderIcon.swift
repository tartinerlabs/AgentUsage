//
//  ProviderIcon.swift
//  AgentUsageKit
//
//  Official provider mark used for attribution across app, widget, and
//  Live Activity surfaces. SF Symbols remain a load-failure fallback only.
//

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

extension Provider {
    /// Template image for the official provider mark, or `iconName` if the asset is missing.
    public var markImage: Image {
        if hasMarkAsset {
            Image(markAssetName, bundle: .module)
                .renderingMode(.template)
        } else {
            Image(systemName: iconName)
        }
    }

    var hasMarkAsset: Bool {
        #if canImport(UIKit)
        UIImage(named: markAssetName, in: .module, compatibleWith: nil) != nil
        #elseif canImport(AppKit)
        Bundle.module.image(forResource: markAssetName) != nil
        #else
        false
        #endif
    }
}

/// Official provider glyph. Tint with `foregroundStyle`; pass `size` to pin
/// points, otherwise the mark tracks the current font like an SF Symbol.
public struct ProviderIcon: View {
    public let provider: Provider
    public let size: CGFloat?
    public let decorative: Bool

    public init(_ provider: Provider, size: CGFloat? = nil, decorative: Bool = true) {
        self.provider = provider
        self.size = size
        self.decorative = decorative
    }

    public var body: some View {
        ZStack {
            if size == nil {
                Image(systemName: "square")
                    .opacity(0)
            }
            provider.markImage
                .resizable()
                .scaledToFit()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(decorative)
        .accessibilityLabel(provider.displayName)
    }
}

extension Label where Title == Text, Icon == ProviderIcon {
    @MainActor
    public init(_ provider: Provider) {
        self.init {
            Text(provider.displayName)
        } icon: {
            ProviderIcon(provider)
        }
    }
}
