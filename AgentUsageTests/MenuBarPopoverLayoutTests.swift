//
//  MenuBarPopoverLayoutTests.swift
//  AgentUsageTests
//

#if os(macOS)
import CoreGraphics
import Testing
@testable import AgentUsage

@Suite("MenuBarPopoverLayout")
struct MenuBarPopoverLayoutTests {
    private typealias Layout = MenuBarPopoverLayout

    @Test func railMinimumCountsEveryTabActionAndGap() {
        // 24 padding + 5 tabs × 30 + 3 actions × 28 + 8 spacer + 8 gaps × 8.
        #expect(Layout.railMinimumHeight(providerCount: 4) == 330)
        // Each provider adds a tab and a gap.
        #expect(Layout.railMinimumHeight(providerCount: 5) == 368)
        #expect(Layout.railMinimumHeight(providerCount: 0) == 178)
    }

    @Test func pageFitsItsContentBetweenTheRailAndTheCap() {
        let height = Layout.scrollHeight(pageContentHeight: 400, chromeHeight: 33, providerCount: 4)
        #expect(height == 400)
    }

    @Test func tallPagesAreCappedSoThePopoverNeverExceedsTheMaximum() {
        let chrome: CGFloat = 33 + 30
        let height = Layout.scrollHeight(pageContentHeight: 1_200, chromeHeight: chrome, providerCount: 4)
        #expect(height + chrome == Layout.maxHeight)
    }

    @Test func shortPagesStillLeaveRoomForTheRail() {
        let chrome: CGFloat = 33
        let height = Layout.scrollHeight(pageContentHeight: 120, chromeHeight: chrome, providerCount: 4)
        #expect(height + chrome == Layout.railMinimumHeight(providerCount: 4))
    }

    @Test func unmeasuredPageStartsAtTheCap() {
        let chrome: CGFloat = 33
        let height = Layout.scrollHeight(pageContentHeight: nil, chromeHeight: chrome, providerCount: 4)
        #expect(height + chrome == Layout.maxHeight)
    }
}
#endif
