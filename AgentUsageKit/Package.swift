// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgentUsageKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "AgentUsageKit",
            targets: ["AgentUsageKit"]
        ),
        .library(
            name: "AgentUsageProviderCore",
            targets: ["AgentUsageProviderCore"]
        ),
    ],
    targets: [
        .target(
            name: "AgentUsageKit"
        ),
        .target(
            name: "AgentUsageProviderCore",
            dependencies: ["AgentUsageKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AgentUsageKitTests",
            dependencies: ["AgentUsageKit"]
        ),
        .testTarget(
            name: "AgentUsageProviderCoreTests",
            dependencies: ["AgentUsageProviderCore", "AgentUsageKit"],
            swiftSettings: [
                .enableExperimentalFeature("SwiftTesting")
            ]
        ),
    ]
)
