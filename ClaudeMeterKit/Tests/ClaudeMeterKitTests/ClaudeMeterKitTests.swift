//
//  ClaudeMeterKitTests.swift
//  ClaudeMeterKit
//

import Testing
@testable import ClaudeMeterKit

@Test func usageWindowTypeDisplayName() async throws {
    #expect(UsageWindowType.session.displayName == "Current session")
    #expect(UsageWindowType.opus.displayName == "All models")
    #expect(UsageWindowType.sonnet.displayName == "Sonnet")
}

@Test func usageStatusLabels() async throws {
    #expect(UsageStatus.onTrack.label == "Low")
    #expect(UsageStatus.warning.label == "Moderate")
    #expect(UsageStatus.critical.label == "High")
}
