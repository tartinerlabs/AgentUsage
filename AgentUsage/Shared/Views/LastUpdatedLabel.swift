//
//  LastUpdatedLabel.swift
//  AgentUsage
//
//  Compact "Updated X ago" label that signals when the displayed usage is
//  cached/offline rather than a fresh fetch. Used by the macOS menu bar footer
//  and the Dashboard tab header so both surfaces read consistently.
//

import SwiftUI

struct LastUpdatedLabel: View {
    /// Already-formatted relative time, e.g. "just now" or "4m ago".
    let relativeText: String
    /// Data currently on screen came from the cache, not a live fetch.
    let isCached: Bool
    /// Device has no network connection.
    let isOffline: Bool
    /// Font for the icon + text (call sites use different sizes).
    var font: Font = .caption2
    /// Style used when the data is live (each surface has its own neutral tone).
    var neutralStyle: AnyShapeStyle = AnyShapeStyle(.tertiary)

    private var isStale: Bool { isCached || isOffline }

    var body: some View {
        HStack(spacing: 4) {
            if isStale {
                Image(systemName: isOffline ? "wifi.slash" : "clock.arrow.circlepath")
            }
            Text("Updated \(relativeText)")
        }
        .font(font)
        .foregroundStyle(isStale ? AnyShapeStyle(.orange) : neutralStyle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOffline ? "Offline, showing cached data"
                            : isCached ? "Showing cached data" : "Last updated")
        .accessibilityValue("Updated \(relativeText)")
    }
}
