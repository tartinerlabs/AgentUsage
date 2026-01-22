//
//  ClaudeMeterKitTests.swift
//  ClaudeMeterKit
//

import Testing
import Foundation
@testable import ClaudeMeterKit

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

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [UsageStatus.onTrack, .warning, .critical] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(UsageStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - UsageWindowType Tests

@Suite("UsageWindowType")
struct UsageWindowTypeTests {
    @Test func displayNames() {
        #expect(UsageWindowType.session.displayName == "Current session")
        #expect(UsageWindowType.opus.displayName == "All models")
        #expect(UsageWindowType.sonnet.displayName == "Sonnet")
    }

    @Test func totalDurations() {
        // Session: 5 hours
        #expect(UsageWindowType.session.totalDuration == 5 * 60 * 60)

        // Opus: 7 days
        #expect(UsageWindowType.opus.totalDuration == 7 * 24 * 60 * 60)

        // Sonnet: 7 days
        #expect(UsageWindowType.sonnet.totalDuration == 7 * 24 * 60 * 60)
    }

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in [UsageWindowType.session, .opus, .sonnet] {
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
    }

    @Test func sonnetCanBeNil() {
        let now = Date()
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: nil, fetchedAt: now)

        #expect(snapshot.sonnet == nil)
    }

    @Test func placeholderHasReasonableValues() {
        let placeholder = UsageSnapshot.placeholder

        #expect(placeholder.session.utilization == 45)
        #expect(placeholder.opus.utilization == 32)
        #expect(placeholder.sonnet?.utilization == 28)
        #expect(placeholder.session.windowType == .session)
        #expect(placeholder.opus.windowType == .opus)
        #expect(placeholder.sonnet?.windowType == .sonnet)
    }

    @Test func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let now = Date(timeIntervalSince1970: 1700000000)
        let session = UsageWindow(utilization: 30, resetsAt: now, windowType: .session)
        let opus = UsageWindow(utilization: 50, resetsAt: now, windowType: .opus)
        let sonnet = UsageWindow(utilization: 40, resetsAt: now, windowType: .sonnet)

        let snapshot = UsageSnapshot(session: session, opus: opus, sonnet: sonnet, fetchedAt: now)
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        #expect(decoded.session.utilization == 30)
        #expect(decoded.opus.utilization == 50)
        #expect(decoded.sonnet?.utilization == 40)
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
    }
}
