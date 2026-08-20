//
//  AgentUsageKitTests.swift
//  AgentUsageKit
//

import Testing
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import AgentUsageKit

private func expectSameColor(
    _ actual: Color,
    _ expected: Color,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let environment = EnvironmentValues()
    let actual = actual.resolve(in: environment)
    let expected = expected.resolve(in: environment)
    let tolerance: Float = 0.0001

    #expect(abs(actual.red - expected.red) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.green - expected.green) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.blue - expected.blue) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.opacity - expected.opacity) < tolerance, sourceLocation: sourceLocation)
}

private func resolvedRGB(_ color: Color, colorScheme: ColorScheme) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    #if os(macOS)
    let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    appearance.performAsCurrentDrawingAppearance {
        NSColor(color).usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    }
    return (red, green, blue, alpha)
    #else
    let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
    #endif
}

private func expectResolvedColor(
    _ actual: Color,
    _ expected: Color,
    colorScheme: ColorScheme,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = resolvedRGB(actual, colorScheme: colorScheme)
    let expected = resolvedRGB(expected, colorScheme: colorScheme)
    let tolerance: CGFloat = 0.0001

    #expect(abs(actual.0 - expected.0) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.1 - expected.1) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.2 - expected.2) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(actual.3 - expected.3) < tolerance, sourceLocation: sourceLocation)
}

// MARK: - Design Token Tests

@Suite("AgentUsageColors")
struct AgentUsageColorsTests {
    @Test func fixedApplicationRolesMatchDesignSystem() {
        expectSameColor(
            AgentUsageColors.iconPacificBlue,
            Color(red: 113 / 255, green: 151 / 255, blue: 212 / 255)
        )
        expectSameColor(
            AgentUsageColors.iconGraphite,
            Color(red: 55 / 255, green: 58 / 255, blue: 65 / 255)
        )
        expectSameColor(
            AgentUsageColors.iconIce,
            Color(red: 245 / 255, green: 246 / 255, blue: 248 / 255)
        )
        expectSameColor(
            AgentUsageColors.iconBackground,
            Color(red: 250 / 255, green: 244 / 255, blue: 239 / 255)
        )
        expectSameColor(
            AgentUsageColors.brandSecondary,
            Color(red: 113 / 255, green: 151 / 255, blue: 212 / 255)
        )
        expectSameColor(
            AgentUsageColors.brandBackground,
            Color(red: 244 / 255, green: 243 / 255, blue: 238 / 255)
        )
        expectSameColor(
            AgentUsageColors.extraUsageAccent,
            Color(red: 139 / 255, green: 94 / 255, blue: 131 / 255)
        )
        expectSameColor(extraUsageAccentColor, AgentUsageColors.extraUsageAccent)
    }

    @Test func usageProgressUsesPacificBlueInDarkAppearance() {
        let ink = Color(red: 59 / 255, green: 107 / 255, blue: 206 / 255)
        expectResolvedColor(AgentUsageColors.usageProgress, ink, colorScheme: .light)
        expectResolvedColor(
            AgentUsageColors.usageProgress,
            AgentUsageColors.iconPacificBlue,
            colorScheme: .dark
        )
    }
}

@Suite("UsageProgressBar")
struct UsageProgressBarTests {
    @Test @MainActor func progressIsClampedToValidGaugeRange() {
        #expect(UsageProgressBar(progress: -0.1).progress == 0)
        #expect(UsageProgressBar(progress: 0.42).progress == 0.42)
        #expect(UsageProgressBar(progress: 1.1).progress == 1)
    }
}

// MARK: - UsageStatus Tests

@Suite("UsageStatus")
struct UsageStatusTests {
    @Test func labels() {
        #expect(UsageStatus.onTrack.label == "Low")
        #expect(UsageStatus.warning.label == "Moderate")
        #expect(UsageStatus.critical.label == "High")
    }

    @Test func icons() {
        #expect(UsageStatus.onTrack.icon == "checkmark.circle.fill")
        #expect(UsageStatus.warning.icon == "exclamationmark.triangle.fill")
        #expect(UsageStatus.critical.icon == "xmark.circle.fill")
    }

    @Test func colorsUseSystemSemanticRoles() {
        expectSameColor(UsageStatus.onTrack.color, .green)
        expectSameColor(UsageStatus.warning.color, .orange)
        expectSameColor(UsageStatus.critical.color, .red)
    }

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [UsageStatus.onTrack, .warning, .critical] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(UsageStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    @Test func comparableOrdersBySeverity() {
        #expect(UsageStatus.onTrack < UsageStatus.warning)
        #expect(UsageStatus.warning < UsageStatus.critical)
        #expect(UsageStatus.onTrack < UsageStatus.critical)
        #expect(max(UsageStatus.onTrack, UsageStatus.critical) == .critical)
    }
}

@Suite("UsageWindow.Trend")
struct UsageWindowTrendTests {
    @Test func presentationMappingsStayInParityAcrossSurfaces() {
        #expect(UsageWindow.Trend.increasing.icon == "arrow.up.right")
        #expect(UsageWindow.Trend.stable.icon == "arrow.right")
        #expect(UsageWindow.Trend.decreasing.icon == "arrow.down.right")

        #expect(UsageWindow.Trend.increasing.accessibilityLabel == "increasing")
        #expect(UsageWindow.Trend.stable.accessibilityLabel == "stable")
        #expect(UsageWindow.Trend.decreasing.accessibilityLabel == "decreasing")

        expectSameColor(UsageWindow.Trend.increasing.color, .orange)
        expectSameColor(UsageWindow.Trend.stable.color, .secondary)
        expectSameColor(UsageWindow.Trend.decreasing.color, .green)
    }
}

// MARK: - UsageWindowType Tests

@Suite("Provider")
struct ProviderTests {
    @Test func presentationMappingsMatchDesignSystem() {
        #expect(Provider.claude.displayName == "Claude")
        #expect(Provider.claude.iconName == "sparkles")
        #expect(Provider.claude.markAssetName == "ClaudeProviderMark")

        #expect(Provider.codex.displayName == "Codex")
        #expect(Provider.codex.iconName == "chevron.left.forwardslash.chevron.right")
        #expect(Provider.codex.markAssetName == "CodexProviderMark")

        #expect(Provider.openCode.iconName == "curlybraces")
        #expect(Provider.openCodeGo.iconName == "curlybraces")
        #expect(Provider.openCode.markAssetName == "OpenCodeProviderMark")
        #expect(Provider.openCodeGo.markAssetName == "OpenCodeProviderMark")

        #expect(Provider.cursor.displayName == "Cursor")
        #expect(Provider.cursor.iconName == "cursorarrow")
        #expect(Provider.cursor.markAssetName == "CursorProviderMark")

        #expect(Provider.grok.displayName == "Grok")
        #expect(Provider.grok.iconName == "bolt.fill")
        #expect(Provider.grok.markAssetName == "GrokProviderMark")

        #expect(Set(Provider.allCases.map(\.markAssetName)).count == 5)
        for provider in Provider.allCases {
            #expect(provider.hasMarkAsset)
        }
    }

    @Test func linksAreProviderMetadataNotViewSwitches() {
        #expect(Provider.claude.links.map(\.label) == ["Status", "Usage"])
        #expect(Provider.claude.links.map(\.urlString) == [
            "https://status.anthropic.com",
            "https://claude.ai/settings/usage",
        ])

        #expect(Provider.codex.links.map(\.label) == ["Status", "Usage"])
        #expect(Provider.codex.links.map(\.urlString) == [
            "https://status.openai.com",
            "https://platform.openai.com/usage",
        ])

        #expect(Provider.cursor.links.map(\.label) == ["Status", "Dashboard"])
        #expect(Provider.cursor.links.map(\.urlString) == [
            "https://status.cursor.com",
            "https://cursor.com/dashboard",
        ])

        #expect(Provider.grok.links.map(\.label) == ["Status", "Console"])
        #expect(Provider.grok.links.map(\.urlString) == [
            "https://status.x.ai",
            "https://console.x.ai",
        ])

        #expect(Provider.openCode.links.isEmpty)
        #expect(Provider.openCodeGo.links.isEmpty)
        #expect(Provider.claude.links.allSatisfy { $0.url != nil })
    }

    @Test func displayNamesDistinguishOpenCodeOfferings() {
        #expect(Provider.openCode.displayName == "OpenCode Zen")
        #expect(Provider.openCodeGo.displayName == "OpenCode Go")
    }

    @Test func cursorIsAnAdditiveRateWindowOnlyProvider() throws {
        #expect(Provider.cursor.displayName == "Cursor")
        #expect(Provider.cursor.iconName == "cursorarrow")
        #expect(Provider.cursor.capabilities == [.rateWindows])
        #expect(Provider.cursor.supports(.tokenCost) == false)

        let data = try JSONEncoder().encode(Provider.cursor)
        #expect(try JSONDecoder().decode(Provider.self, from: data) == .cursor)
    }

    @Test func grokIsAnAdditiveTokenCostProvider() throws {
        #expect(Provider.grok.displayName == "Grok")
        #expect(Provider.grok.iconName == "bolt.fill")
        #expect(Provider.grok.capabilities == [.tokenCost])
        #expect(Provider.grok.supports(.rateWindows) == false)
        #expect(Provider.grok.pricingProviderKey == "xai")

        let data = try JSONEncoder().encode(Provider.grok)
        #expect(try JSONDecoder().decode(Provider.self, from: data) == .grok)
    }
}

@Suite("UsageActivitySelection")
struct UsageActivitySelectionTests {
    @Test func providerSelectionsRoundTripIncludingCursorCustomWindow() throws {
        let selections = [
            UsageActivitySelection(provider: .claude, windowID: "session"),
            UsageActivitySelection(provider: .codex, windowID: "codex-weekly"),
            UsageActivitySelection(provider: .cursor, windowID: "cursor.dynamic.usage-2026"),
        ]

        let data = try JSONEncoder().encode(selections)
        let decoded = try JSONDecoder().decode([UsageActivitySelection].self, from: data)

        #expect(decoded == selections)
        #expect(decoded.last?.windowID.rawValue == "cursor.dynamic.usage-2026")
    }

    @Test func mostUrgentPrefersCriticalCursorOverClaude() {
        let now = Date()
        let snapshots = [
            snapshot(provider: .claude, utilization: 45, resetsIn: 3_600, now: now, type: .session),
            snapshot(provider: .codex, utilization: 72, resetsIn: 3_600, now: now, type: .codexFiveHour),
            snapshot(provider: .cursor, utilization: 92, resetsIn: 86_400, now: now, windowID: "cursor.monthly"),
        ]

        let selection = UsageActivitySelection.mostUrgent(in: snapshots, now: now)

        #expect(selection?.provider == .cursor)
        #expect(selection?.windowID.rawValue == "cursor.monthly")
    }

    @Test func mostUrgentIgnoresExpiredWindowsAndSkipsGrok() {
        let now = Date()
        let snapshots = [
            snapshot(provider: .claude, utilization: 99, resetsIn: -60, now: now, type: .session),
            snapshot(provider: .codex, utilization: 40, resetsIn: 3_600, now: now, type: .codexFiveHour),
            ProviderUsageSnapshot(provider: .grok, windows: [], fetchedAt: now),
        ]

        let selection = UsageActivitySelection.mostUrgent(in: snapshots, now: now)

        #expect(selection?.provider == .codex)
        #expect(selection?.windowID.rawValue == UsageWindowType.codexFiveHour.rawValue)
    }

    @Test func mostUrgentReturnsNilWhenNoLiveWindows() {
        let now = Date()
        let snapshots = [
            snapshot(provider: .claude, utilization: 80, resetsIn: -60, now: now, type: .session),
        ]

        #expect(UsageActivitySelection.mostUrgent(in: snapshots, now: now) == nil)
        #expect(UsageActivitySelection.mostUrgent(in: [], now: now) == nil)
    }

    @Test func glanceWindowsStayInCanonicalOrderAndHonorPreferredWindow() {
        let now = Date()
        let claude = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                UsageWindow(utilization: 20, resetsAt: now.addingTimeInterval(3_600), windowType: .session),
                UsageWindow(utilization: 88, resetsAt: now.addingTimeInterval(86_400), windowType: .opus),
            ],
            fetchedAt: now
        )
        let codex = snapshot(
            provider: .codex,
            utilization: 50,
            resetsIn: 3_600,
            now: now,
            type: .codexFiveHour
        )
        let cursor = snapshot(
            provider: .cursor,
            utilization: 10,
            resetsIn: 86_400,
            now: now,
            windowID: "cursor.monthly"
        )

        let preferred = UsageActivitySelection(provider: .claude, windowID: "session")
        let glances = UsageActivitySelection.glanceWindows(
            in: [cursor, claude, codex],
            preferring: preferred,
            now: now
        )

        #expect(glances.map(\.provider) == [.claude, .codex, .cursor])
        #expect(glances.first?.window.windowID.rawValue == "session")
        #expect(glances.contains { $0.provider == .grok } == false)
    }

    @Test func primaryWindowFallsBackToMostUrgentWhenPreferredIsExpired() {
        let now = Date()
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 30,
                    resetsAt: now.addingTimeInterval(-60),
                    windowType: .codexFiveHour
                ),
                UsageWindow(
                    utilization: 81,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowType: .codexWeekly
                ),
            ],
            fetchedAt: now
        )
        let preferred = UsageActivitySelection(
            provider: .codex,
            windowID: UsageWindowID(rawValue: UsageWindowType.codexFiveHour.rawValue)
        )

        let window = snapshot.primaryWindow(preferring: preferred, now: now)

        #expect(window?.windowType == .codexWeekly)
    }

    private func snapshot(
        provider: Provider,
        utilization: Double,
        resetsIn: TimeInterval,
        now: Date,
        type: UsageWindowType? = nil,
        windowID: UsageWindowID? = nil
    ) -> ProviderUsageSnapshot {
        let window: UsageWindow
        if let type {
            window = UsageWindow(
                utilization: utilization,
                resetsAt: now.addingTimeInterval(resetsIn),
                windowType: type
            )
        } else {
            window = UsageWindow(
                utilization: utilization,
                resetsAt: now.addingTimeInterval(resetsIn),
                windowID: windowID ?? "custom",
                displayName: "Usage",
                totalDuration: 86_400
            )
        }
        return ProviderUsageSnapshot(provider: provider, windows: [window], fetchedAt: now)
    }
}

@Suite("UsageWindowType")
struct UsageWindowTypeTests {
    @Test func displayNames() {
        #expect(UsageWindowType.session.displayName == "Current session")
        #expect(UsageWindowType.opus.displayName == "All models")
        #expect(UsageWindowType.sonnet.displayName == "Sonnet")
        #expect(UsageWindowType.fable.displayName == "Fable")

        #expect(UsageWindowType.openCodeGoFiveHour.displayName == "Rolling Usage")
        #expect(UsageWindowType.openCodeGoWeekly.displayName == "Weekly Usage")
        #expect(UsageWindowType.openCodeGoMonthly.displayName == "Monthly Usage")
    }

    @Test func totalDurations() {
        // Session: 5 hours
        #expect(UsageWindowType.session.totalDuration == 5 * 60 * 60)

        // Opus: 7 days
        #expect(UsageWindowType.opus.totalDuration == 7 * 24 * 60 * 60)

        // Sonnet: 7 days
        #expect(UsageWindowType.sonnet.totalDuration == 7 * 24 * 60 * 60)

        // Fable: 7 days
        #expect(UsageWindowType.fable.totalDuration == 7 * 24 * 60 * 60)
    }

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in [UsageWindowType.session, .opus, .sonnet, .fable] {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(UsageWindowType.self, from: data)
            #expect(decoded == type)
        }
    }
}

// MARK: - UsageWindow Tests

@Suite("UsageWindow")
struct UsageWindowTests {

    // MARK: - Basic Properties

    @Test func percentUsed() {
        let window = UsageWindow(utilization: 45.7, resetsAt: Date(), windowType: .session)
        #expect(window.percentUsed == 45)
    }

    @Test func percentUsedRoundsDown() {
        let window = UsageWindow(utilization: 99.9, resetsAt: Date(), windowType: .session)
        #expect(window.percentUsed == 99)
    }

    @Test func isAtLimitWhenExactly100() {
        let window = UsageWindow(utilization: 100, resetsAt: Date(), windowType: .session)
        #expect(window.isAtLimit == true)
    }

    @Test func isAtLimitWhenOver100() {
        let window = UsageWindow(utilization: 105, resetsAt: Date(), windowType: .session)
        #expect(window.isAtLimit == true)
    }

    @Test func isNotAtLimitWhenBelow100() {
        let window = UsageWindow(utilization: 99.9, resetsAt: Date(), windowType: .session)
        #expect(window.isAtLimit == false)
    }

    // MARK: - Extra Usage

    @Test func isUsingExtraUsageWhenOver100() {
        let window = UsageWindow(utilization: 115, resetsAt: Date(), windowType: .session)
        #expect(window.isUsingExtraUsage == true)
    }

    @Test func isNotUsingExtraUsageAt100() {
        let window = UsageWindow(utilization: 100, resetsAt: Date(), windowType: .session)
        #expect(window.isUsingExtraUsage == false)
    }

    @Test func isNotUsingExtraUsageBelow100() {
        let window = UsageWindow(utilization: 50, resetsAt: Date(), windowType: .session)
        #expect(window.isUsingExtraUsage == false)
    }

    @Test func extraUsagePercentCalculation() {
        let window = UsageWindow(utilization: 115.7, resetsAt: Date(), windowType: .session)
        #expect(window.extraUsagePercent == 15)
    }

    @Test func extraUsagePercentZeroWhenBelow100() {
        let window = UsageWindow(utilization: 80, resetsAt: Date(), windowType: .session)
        #expect(window.extraUsagePercent == 0)
    }

    @Test func extraUsagePercentZeroAtExactly100() {
        let window = UsageWindow(utilization: 100, resetsAt: Date(), windowType: .session)
        #expect(window.extraUsagePercent == 0)
    }

    // MARK: - Normalized (0-1 range for gauges)

    @Test func normalizedClampsTo0() {
        let window = UsageWindow(utilization: -10, resetsAt: Date(), windowType: .session)
        #expect(window.normalized == 0)
    }

    @Test func normalizedClampsTo1() {
        let window = UsageWindow(utilization: 150, resetsAt: Date(), windowType: .session)
        #expect(window.normalized == 1)
    }

    @Test func normalizedConvertsCorrectly() {
        let window = UsageWindow(utilization: 50, resetsAt: Date(), windowType: .session)
        #expect(window.normalized == 0.5)
    }

    // MARK: - Time Until Reset

    @Test func timeUntilResetShowsDaysAndHours() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 24 * 60 * 60 + 3 * 60 * 60) // 2 days, 3 hours
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .opus)

        #expect(window.timeUntilReset(from: now) == "2d 3h")
    }

    @Test func timeUntilResetShowsHoursAndMinutes() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 60 * 60 + 45 * 60) // 3 hours, 45 minutes
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.timeUntilReset(from: now) == "3h 45m")
    }

    @Test func timeUntilResetShowsOnlyMinutes() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(30 * 60) // 30 minutes
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.timeUntilReset(from: now) == "30m")
    }

    @Test func timeUntilResetShowsNowWhenPast() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-60) // 1 minute ago
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.timeUntilReset(from: now) == "now")
    }

    @Test func timeUntilResetShowsZeroMinutes() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(30) // 30 seconds
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.timeUntilReset(from: now) == "0m")
    }

    // MARK: - Status Calculation (Complex Logic)

    @Test func statusCriticalAt90Percent() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4 * 60 * 60) // 4 hours left
        let window = UsageWindow(utilization: 90, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .critical)
    }

    @Test func statusCriticalAt100Percent() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4 * 60 * 60)
        let window = UsageWindow(utilization: 100, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .critical)
    }

    @Test func statusWarningAt75Percent() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4 * 60 * 60)
        let window = UsageWindow(utilization: 75, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .warning)
    }

    @Test func statusWarningAt89Percent() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(4 * 60 * 60)
        let window = UsageWindow(utilization: 89, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .warning)
    }

    @Test func statusOnTrackWhenResetPassed() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-60) // Reset already passed
        let window = UsageWindow(utilization: 95, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .onTrack)
    }

    // MARK: - Status Pace Calculation (below 75%)

    @Test func statusOnTrackWhenOnPace() {
        // Session: 5 hours total
        // If 2.5 hours elapsed (50% time), 50% usage should be on track
        let now = Date()
        let timeRemaining: TimeInterval = 2.5 * 60 * 60 // 50% time remaining
        let resetsAt = now.addingTimeInterval(timeRemaining)
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .onTrack)
    }

    @Test func statusOnTrackWhenSlightlyAheadOfPace() {
        // Session: 5 hours total
        // If 2.5 hours elapsed (50% time), 55% usage (5% ahead) should still be on track
        let now = Date()
        let timeRemaining: TimeInterval = 2.5 * 60 * 60
        let resetsAt = now.addingTimeInterval(timeRemaining)
        let window = UsageWindow(utilization: 55, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .onTrack)
    }

    @Test func statusWarningWhenModeratelyAheadOfPace() {
        // Session: 5 hours total
        // If 2.5 hours elapsed (50% time), 70% usage (20% ahead) should be warning
        let now = Date()
        let timeRemaining: TimeInterval = 2.5 * 60 * 60
        let resetsAt = now.addingTimeInterval(timeRemaining)
        let window = UsageWindow(utilization: 70, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .warning)
    }

    @Test func statusCriticalWhenFarAheadOfPace() {
        // Session: 5 hours total
        // If 1 hour elapsed (20% time), 60% usage (40% ahead) should be critical
        let now = Date()
        let timeRemaining: TimeInterval = 4 * 60 * 60 // 80% time remaining
        let resetsAt = now.addingTimeInterval(timeRemaining)
        let window = UsageWindow(utilization: 60, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .critical)
    }

    @Test func statusOnTrackWhenBehindPace() {
        // Session: 5 hours total
        // If 4 hours elapsed (80% time), 50% usage should be on track (behind pace)
        let now = Date()
        let timeRemaining: TimeInterval = 1 * 60 * 60 // 20% time remaining
        let resetsAt = now.addingTimeInterval(timeRemaining)
        let window = UsageWindow(utilization: 50, resetsAt: resetsAt, windowType: .session)

        #expect(window.status == .onTrack)
    }

    // MARK: - Codable

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let resetsAt = Date(timeIntervalSince1970: 1700000000)
        let window = UsageWindow(utilization: 45.5, resetsAt: resetsAt, windowType: .opus)

        let data = try encoder.encode(window)
        let decoded = try decoder.decode(UsageWindow.self, from: data)

        #expect(decoded.utilization == 45.5)
        #expect(decoded.resetsAt == resetsAt)
        #expect(decoded.windowType == .opus)
    }
}

// MARK: - UsageSnapshot Tests

@Suite("UsageSnapshot")
struct UsageSnapshotTests {

    @Test func initializesWithAllWindows() {
        let now = Date()
        let session = UsageWindow(utilization: 30, resetsAt: now.addingTimeInterval(3600), windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now.addingTimeInterval(86400), windowType: .opus)
        let sonnet = UsageWindow(utilization: 40, resetsAt: now.addingTimeInterval(86400), windowType: .sonnet)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: sonnet, fetchedAt: now)

        #expect(snapshot.session.utilization == 30)
        #expect(snapshot.opus.utilization == 50)
        #expect(snapshot.sonnet?.utilization == 40)
        #expect(snapshot.fetchedAt == now)
        #expect(snapshot.hasExtraUsageEnabled == false)
    }

    @Test func hasExtraUsageEnabledDefaultsFalse() {
        let now = Date()
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)
        #expect(snapshot.hasExtraUsageEnabled == false)
    }

    @Test func hasExtraUsageEnabledWhenCostPresent() {
        let now = Date()
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)
        let cost = ExtraUsageCost(used: 1.50, limit: 50.0, currencyCode: "USD")

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, extraUsage: cost, fetchedAt: now)
        #expect(snapshot.hasExtraUsageEnabled == true)
        #expect(snapshot.extraUsage?.used == 1.50)
        #expect(snapshot.extraUsage?.limit == 50.0)
    }

    @Test func isExtraUsageActiveWhenSessionOver100() {
        let now = Date()
        let session = UsageWindow(utilization: 115, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)
        #expect(snapshot.isExtraUsageActive == true)
    }

    @Test func isExtraUsageActiveWhenOpusOver100() {
        let now = Date()
        let session = UsageWindow(utilization: 50, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 110, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)
        #expect(snapshot.isExtraUsageActive == true)
    }

    @Test func isExtraUsageActiveWhenSonnetOver100() {
        let now = Date()
        let session = UsageWindow(utilization: 50, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)
        let sonnet = UsageWindow(utilization: 120, resetsAt: now, windowType: .sonnet)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: sonnet, fetchedAt: now)
        #expect(snapshot.isExtraUsageActive == true)
    }

    @Test func isExtraUsageNotActiveWhenAllBelow100() {
        let now = Date()
        let session = UsageWindow(utilization: 50, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 80, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)
        #expect(snapshot.isExtraUsageActive == false)
    }

    // MARK: - allWindowsExpired

    @Test func allWindowsExpiredTrueWhenAllWindowsPast() {
        let past = Date().addingTimeInterval(-3600)
        let session = UsageWindow(utilization: 50, resetsAt: past, windowType: .session)
        let opus = UsageWindow(utilization: 30, resetsAt: past, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: Date())
        #expect(snapshot.allWindowsExpired == true)
    }

    @Test func allWindowsExpiredFalseWhenAnyWindowFuture() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)
        let session = UsageWindow(utilization: 50, resetsAt: past, windowType: .session)
        let opus = UsageWindow(utilization: 30, resetsAt: future, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: Date())
        #expect(snapshot.allWindowsExpired == false)
    }

    @Test func allWindowsExpiredFalseWhenAllWindowsFuture() {
        let future = Date().addingTimeInterval(3600)
        let session = UsageWindow(utilization: 50, resetsAt: future, windowType: .session)
        let opus = UsageWindow(utilization: 30, resetsAt: future, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: Date())
        #expect(snapshot.allWindowsExpired == false)
    }

    @Test func allWindowsExpiredChecksOptionalWindows() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)
        let session = UsageWindow(utilization: 50, resetsAt: past, windowType: .session)
        let opus = UsageWindow(utilization: 30, resetsAt: past, windowType: .opus)
        let sonnet = UsageWindow(utilization: 20, resetsAt: future, windowType: .sonnet)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: sonnet, fetchedAt: Date())
        #expect(snapshot.allWindowsExpired == false, "future sonnet window should keep snapshot fresh")
    }

    // MARK: - UsageWindow.isExpired

    @Test func usageWindowIsExpiredTrueForPastReset() {
        let now = Date()
        let window = UsageWindow(
            utilization: 97,
            resetsAt: now.addingTimeInterval(-60),
            windowType: .session
        )
        #expect(window.isExpired(from: now) == true)
    }

    @Test func usageWindowIsExpiredFalseForFutureReset() {
        let now = Date()
        let window = UsageWindow(
            utilization: 42,
            resetsAt: now.addingTimeInterval(3600),
            windowType: .session
        )
        #expect(window.isExpired(from: now) == false)
    }

    @Test func extraUsageCostPercentUsed() {
        let cost = ExtraUsageCost(used: 25.0, limit: 50.0, currencyCode: "USD")
        #expect(cost.percentUsed == 50.0)
    }

    @Test func extraUsageCostPercentUsedZeroLimit() {
        let cost = ExtraUsageCost(used: 10.0, limit: 0, currencyCode: "USD")
        #expect(cost.percentUsed == 0)
    }

    @Test func extraUsageCostNormalized() {
        let cost = ExtraUsageCost(used: 25.0, limit: 50.0, currencyCode: "USD")
        #expect(cost.normalized == 0.5)
    }

    @Test func extraUsageCostNormalizedClampsTo1() {
        let cost = ExtraUsageCost(used: 75.0, limit: 50.0, currencyCode: "USD")
        #expect(cost.normalized == 1.0)
    }

    @Test func extraUsageCostFormattedAmounts() {
        let cost = ExtraUsageCost(used: 1.50, limit: 50.0, currencyCode: "USD")
        #expect(cost.formattedUsed.contains("1.50"))
        #expect(cost.formattedLimit.contains("50.00"))
    }

    @Test func extraUsageCostCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cost = ExtraUsageCost(used: 12.34, limit: 100.0, currencyCode: "USD")

        let data = try encoder.encode(cost)
        let decoded = try decoder.decode(ExtraUsageCost.self, from: data)

        #expect(decoded.used == 12.34)
        #expect(decoded.limit == 100.0)
        #expect(decoded.currencyCode == "USD")
    }

    @Test func sonnetCanBeNil() {
        let now = Date()
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)

        #expect(snapshot.sonnet == nil)
    }

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let now = Date(timeIntervalSince1970: 1700000000)
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)
        let sonnet = UsageWindow(utilization: 40, resetsAt: now, windowType: .sonnet)
        let fable = UsageWindow(utilization: 16, resetsAt: now, windowType: .fable)

        let cost = ExtraUsageCost(used: 5.0, limit: 50.0, currencyCode: "USD")
        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: sonnet, fable: fable, extraUsage: cost, fetchedAt: now)
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        #expect(decoded.session.utilization == 30)
        #expect(decoded.opus.utilization == 50)
        #expect(decoded.sonnet?.utilization == 40)
        #expect(decoded.fable?.utilization == 16)
        #expect(decoded.fable?.windowType == .fable)
        #expect(decoded.hasExtraUsageEnabled == true)
        #expect(decoded.extraUsage?.used == 5.0)
        #expect(decoded.extraUsage?.limit == 50.0)
        #expect(decoded.extraUsage?.currencyCode == "USD")
        #expect(decoded.fetchedAt == now)
    }

    @Test func codableWithNilSonnet() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let now = Date(timeIntervalSince1970: 1700000000)
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        #expect(decoded.sonnet == nil)
        #expect(decoded.hasExtraUsageEnabled == false)
    }

    @Test func codableBackwardsCompatibleWithoutExtraUsage() throws {
        // Simulate decoding old cached data that doesn't have extraUsage
        let json = """
        {
            "session": {"utilization": 30, "resetsAt": 0, "windowType": "session"},
            "opus": {"utilization": 50, "resetsAt": 0, "windowType": "opus"},
            "fetchedAt": 0
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        #expect(decoded.extraUsage == nil)
        #expect(decoded.hasExtraUsageEnabled == false)
    }
}
