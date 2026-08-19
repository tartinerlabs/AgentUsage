//
//  Provider.swift
//  AgentUsageKit
//
//  Identifies an AI coding tool whose usage AgentUsage can monitor.
//

import Foundation

// MARK: - Provider

/// An AI coding tool whose usage AgentUsage monitors.
public enum Provider: String, Sendable, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case openCode
    case openCodeGo
    case cursor
    case grok

    public var id: String { rawValue }

    /// User-facing name.
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCode: "OpenCode Zen"
        case .openCodeGo: "OpenCode Go"
        case .cursor: "Cursor"
        case .grok: "Grok"
        }
    }

    /// SF Symbol used as a fallback glyph for the provider.
    public var iconName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .openCode, .openCodeGo: "curlybraces"
        case .cursor: "cursorarrow"
        case .grok: "bolt.fill"
        }
    }

    /// Asset catalog name for the compact menu-bar mark, when one exists.
    ///
    /// Providers without a dedicated mark render `iconName` instead.
    public var menuBarMarkAssetName: String? {
        switch self {
        case .claude: "ClaudeProviderMark"
        case .codex: "CodexProviderMark"
        case .openCode, .openCodeGo, .cursor, .grok: nil
        }
    }

    /// External status and console links shown on the provider detail surface.
    public var links: [ProviderLink] {
        switch self {
        case .claude:
            [
                ProviderLink(label: "Status", urlString: "https://status.anthropic.com"),
                ProviderLink(label: "Usage", urlString: "https://claude.ai/settings/usage"),
            ]
        case .codex:
            [
                ProviderLink(label: "Status", urlString: "https://status.openai.com"),
                ProviderLink(label: "Usage", urlString: "https://platform.openai.com/usage"),
            ]
        case .openCode, .openCodeGo:
            []
        case .cursor:
            [
                ProviderLink(label: "Status", urlString: "https://status.cursor.com"),
                ProviderLink(label: "Dashboard", urlString: "https://cursor.com/dashboard"),
            ]
        case .grok:
            [
                ProviderLink(label: "Status", urlString: "https://status.x.ai"),
                ProviderLink(label: "Console", urlString: "https://console.x.ai"),
            ]
        }
    }

    // MARK: Capabilities

    /// A kind of usage data a provider can surface.
    public enum Capability: Sendable, Hashable {
        /// Rate-limit / quota windows with utilization and reset times.
        case rateWindows
        /// Token usage and computed cost from local logs.
        case tokenCost
    }

    public var capabilities: Set<Capability> {
        switch self {
        case .claude: [.rateWindows, .tokenCost]
        case .codex: [.rateWindows, .tokenCost]
        case .openCode: [.rateWindows, .tokenCost]
        case .openCodeGo: [.rateWindows, .tokenCost]
        case .cursor: [.rateWindows]
        case .grok: [.tokenCost]
        }
    }

    public func supports(_ capability: Capability) -> Bool {
        capabilities.contains(capability)
    }

    /// Default pricing-table key used by `ModelPricing`.
    ///
    /// OpenCode is multi-upstream, so its real pricing key is read per session
    /// from each session's `model.providerID`; this is only the fallback.
    public var pricingProviderKey: String {
        switch self {
        case .claude: "anthropic"
        case .codex: "openai"
        case .openCode, .openCodeGo: "openai"
        case .cursor: "cursor"
        case .grok: "xai"
        }
    }

    /// Visual family used to group related offerings without merging their quota state.
    public var family: Provider {
        switch self {
        case .openCodeGo: .openCode
        default: self
        }
    }
}

/// An external status or console destination for a provider.
public struct ProviderLink: Sendable, Hashable {
    public let label: String
    public let urlString: String

    public var url: URL? { URL(string: urlString) }

    public init(label: String, urlString: String) {
        self.label = label
        self.urlString = urlString
    }
}
