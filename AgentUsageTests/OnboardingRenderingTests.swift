//
//  OnboardingRenderingTests.swift
//  AgentUsageTests
//

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import AgentUsage

final class OnboardingRenderingTests: XCTestCase {
    @MainActor
    func testMacOnboardingReference() throws {
        let view = DataAccessOnboardingView(
            onComplete: {},
            onSkip: {},
            detectsExistingAccess: false
        )
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 920, height: 680)
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Mac Onboarding Reference"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
