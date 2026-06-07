//
//  CodexUsageServiceTests.swift
//  ClaudeMeterTests
//

#if os(macOS)
import Foundation
import Testing
@testable import ClaudeMeter
@testable import ClaudeMeterKit

@Suite("Codex Usage Service", .serialized)
struct CodexUsageServiceTests {
    @Test func expiredRateLimitWindowsRefreshToZeroUsage() async throws {
        let directory = try Self.temporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primaryReset = Int(now.addingTimeInterval(-60).timeIntervalSince1970)
        let weeklyReset = Int(now.addingTimeInterval(-60).timeIntervalSince1970)
        try Self.writeRollout(
            to: directory,
            primaryUsedPercent: 100,
            primaryReset: primaryReset,
            weeklyUsedPercent: 85,
            weeklyReset: weeklyReset
        )

        let service = CodexUsageService(directories: [directory], now: { now })
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.provider == .codex)
        #expect(snapshot?.fetchedAt == now)
        #expect(snapshot?.windows.count == 2)
        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.utilization == 0)
        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.utilization == 0)
        let primaryWindow = try #require(snapshot?.windows.first { $0.windowType == .codexFiveHour })
        let weeklyWindow = try #require(snapshot?.windows.first { $0.windowType == .codexWeekly })
        #expect(primaryWindow.resetsAt > now)
        #expect(weeklyWindow.resetsAt > now)
    }

    @Test func activeRateLimitWindowsKeepReportedUsage() async throws {
        let directory = try Self.temporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primaryReset = Int(now.addingTimeInterval(60).timeIntervalSince1970)
        let weeklyReset = Int(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        try Self.writeRollout(
            to: directory,
            primaryUsedPercent: 42,
            primaryReset: primaryReset,
            weeklyUsedPercent: 17,
            weeklyReset: weeklyReset
        )

        let service = CodexUsageService(directories: [directory], now: { now })
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.utilization == 42)
        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.utilization == 17)
        #expect(snapshot?.windows.first { $0.windowType == .codexFiveHour }?.resetsAt == Date(timeIntervalSince1970: TimeInterval(primaryReset)))
        #expect(snapshot?.windows.first { $0.windowType == .codexWeekly }?.resetsAt == Date(timeIntervalSince1970: TimeInterval(weeklyReset)))
    }

    @Test func primaryWindowUsesReportedWindowMinutesForFreePlanWeeklyLimit() async throws {
        let directory = try Self.temporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weeklyReset = Int(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        let log = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"free","primary":{"used_percent":33,"window_minutes":10080,"resets_at":\(weeklyReset)},"secondary":null}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let service = CodexUsageService(directories: [directory], now: { now })
        let snapshot = try await service.fetchSnapshot()

        let window = try #require(snapshot?.windows.first)
        #expect(snapshot?.windows.count == 1)
        #expect(window.windowType == .codexWeekly)
        #expect(window.utilization == 33)
    }

    @Test func resetAfterSecondsIsResolvedRelativeToFetchTime() async throws {
        let directory = try Self.temporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let log = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"plus","primary":{"used_percent":"12","window_minutes":"300","reset_after_seconds":"90"},"secondary":null}}}
        """.write(to: log, atomically: true, encoding: .utf8)

        let service = CodexUsageService(directories: [directory], now: { now })
        let snapshot = try await service.fetchSnapshot()

        let window = try #require(snapshot?.windows.first)
        #expect(window.windowType == .codexFiveHour)
        #expect(window.utilization == 12)
        #expect(window.resetsAt == now.addingTimeInterval(90))
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageServiceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeRollout(
        to directory: URL,
        primaryUsedPercent: Int,
        primaryReset: Int,
        weeklyUsedPercent: Int,
        weeklyReset: Int
    ) throws {
        let log = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"plan_type":"plus","primary":{"used_percent":\(primaryUsedPercent),"resets_at":\(primaryReset)},"secondary":{"used_percent":\(weeklyUsedPercent),"resets_at":\(weeklyReset)}}}}
        """.write(to: log, atomically: true, encoding: .utf8)
    }
}
#endif
