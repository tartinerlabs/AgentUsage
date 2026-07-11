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
    ],
    targets: [
        .target(
            name: "AgentUsageKit"
        ),
        .testTarget(
            name: "AgentUsageKitTests",
            dependencies: ["AgentUsageKit"]
        ),
    ]
)
