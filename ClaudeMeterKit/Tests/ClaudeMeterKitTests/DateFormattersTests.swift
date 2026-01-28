//
//  DateFormattersTests.swift
//  ClaudeMeterKitTests
//
//  Unit tests for DateFormatters utility
//

import Testing
import Foundation
@testable import ClaudeMeterKit

@Suite("DateFormatters")
struct DateFormattersTests {

    @Test func relativeDescriptionJustNow() {
        let now = Date()
        let result = DateFormatters.relativeDescription(from: now, to: now)
        #expect(result == "just now")
    }

    @Test func relativeDescriptionWithinOneSecond() {
        let now = Date()
        let past = now.addingTimeInterval(-1)
        let result = DateFormatters.relativeDescription(from: past, to: now)
        #expect(result == "just now")
    }

    @Test func relativeDescriptionMinutesAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-300) // 5 minutes ago
        let result = DateFormatters.relativeDescription(from: past, to: now)
        // RelativeDateTimeFormatter returns localized strings, but should contain "min" or "m"
        #expect(result.contains("min") || result.contains("m"))
    }

    @Test func relativeDescriptionHoursAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-7200) // 2 hours ago
        let result = DateFormatters.relativeDescription(from: past, to: now)
        // Should contain "hr" or "h"
        #expect(result.contains("hr") || result.contains("h"))
    }

    @Test func relativeDescriptionDefaultsToNow() {
        let past = Date().addingTimeInterval(-60)
        let result = DateFormatters.relativeDescription(from: past)
        // Should be non-empty and not "just now"
        #expect(!result.isEmpty)
        #expect(result != "just now")
    }
}
