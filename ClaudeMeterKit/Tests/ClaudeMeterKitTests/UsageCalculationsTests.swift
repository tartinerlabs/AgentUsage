//
//  UsageCalculationsTests.swift
//  ClaudeMeterKitTests
//
//  Unit tests for UsageCalculations utility
//

import Testing
import Foundation
@testable import ClaudeMeterKit

@Suite("UsageCalculations")
struct UsageCalculationsTests {

    // MARK: - Test Helpers

    private func makeWindow(
        utilization: Double,
        resetsAt: Date = Date().addingTimeInterval(3600),
        type: UsageWindowType = .session
    ) -> UsageWindow {
        UsageWindow(utilization: utilization, resetsAt: resetsAt, windowType: type)
    }

    private func makeSnapshot(
        session: Double = 50,
        opus: Double = 50,
        sonnet: Double? = nil
    ) -> UsageSnapshot {
        let sessionWindow = makeWindow(utilization: session, type: .session)
        let opusWindow = makeWindow(utilization: opus, type: .opus)
        let sonnetWindow = sonnet.map { makeWindow(utilization: $0, type: .sonnet) }

        return UsageSnapshot(
            session: sessionWindow,
            opus: opusWindow,
            sonnet: sonnetWindow,
            fetchedAt: Date()
        )
    }

    // MARK: - Overall Status from Windows

    @Test func overallStatusFromWindowsAllOnTrack() {
        let windows: [UsageWindow?] = [
            makeWindow(utilization: 20),
            makeWindow(utilization: 30),
            makeWindow(utilization: 40)
        ]
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .onTrack)
    }

    @Test func overallStatusFromWindowsWithWarning() {
        let windows: [UsageWindow?] = [
            makeWindow(utilization: 20),
            makeWindow(utilization: 80), // Warning level
            makeWindow(utilization: 40)
        ]
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .warning)
    }

    @Test func overallStatusFromWindowsWithCritical() {
        let windows: [UsageWindow?] = [
            makeWindow(utilization: 20),
            makeWindow(utilization: 95), // Critical level
            makeWindow(utilization: 40)
        ]
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .critical)
    }

    @Test func overallStatusFromWindowsCriticalTakesPriority() {
        let windows: [UsageWindow?] = [
            makeWindow(utilization: 20),  // On track
            makeWindow(utilization: 80),  // Warning
            makeWindow(utilization: 95)   // Critical
        ]
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .critical)
    }

    @Test func overallStatusFromWindowsHandlesNil() {
        let windows: [UsageWindow?] = [
            makeWindow(utilization: 20),
            nil,
            makeWindow(utilization: 40)
        ]
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .onTrack)
    }

    @Test func overallStatusFromEmptyWindows() {
        let windows: [UsageWindow?] = []
        let status = UsageCalculations.overallStatus(from: windows)
        #expect(status == .onTrack)
    }

    // MARK: - Overall Status from Snapshot

    @Test func overallStatusFromSnapshotNil() {
        let status = UsageCalculations.overallStatus(from: nil)
        #expect(status == .onTrack)
    }

    @Test func overallStatusFromSnapshotOnTrack() {
        let snapshot = makeSnapshot(session: 20, opus: 30, sonnet: 40)
        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .onTrack)
    }

    @Test func overallStatusFromSnapshotWithWarning() {
        let snapshot = makeSnapshot(session: 20, opus: 80, sonnet: 40)
        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .warning)
    }

    @Test func overallStatusFromSnapshotWithCritical() {
        let snapshot = makeSnapshot(session: 95, opus: 30, sonnet: 40)
        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .critical)
    }

    @Test func overallStatusFromSnapshotWithoutSonnet() {
        let snapshot = makeSnapshot(session: 20, opus: 30, sonnet: nil)
        let status = UsageCalculations.overallStatus(from: snapshot)
        #expect(status == .onTrack)
    }
}
