//
//  Provider.swift
//  AgentUsageKit
//
//  Identifies an AI coding tool whose usage AgentUsage can monitor.
//

import Foundation
import SwiftUI

// MARK: - Provider

/// An AI coding tool whose usage AgentUsage monitors.
public enum Provider: String, Sendable, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case openCode
    case openCodeGo

    public var id: String { rawValue }

    /// User-facing name.
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCode: "OpenCode Zen"
        case .openCodeGo: "OpenCode Go"
        }
    }

    /// SF Symbol used as a fallback glyph for the provider.
    public var iconName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .openCode, .openCodeGo: "curlybraces"
        }
    }

    /// Accent color for provider-specific UI.
    public var accentColor: Color {
        switch self {
        case .claude: Color(red: 217/255, green: 119/255, blue: 87/255)   // Claude clay
        case .codex: Color(red: 16/255, green: 163/255, blue: 127/255)    // OpenAI green
        case .openCode, .openCodeGo: Color(red: 99/255, green: 102/255, blue: 241/255) // Indigo
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
