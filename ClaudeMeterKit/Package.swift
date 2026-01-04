// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeMeterKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "ClaudeMeterKit",
            targets: ["ClaudeMeterKit"]
        ),
    ],
    targets: [
        .target(
            name: "ClaudeMeterKit"
        ),
        .testTarget(
            name: "ClaudeMeterKitTests",
            dependencies: ["ClaudeMeterKit"]
        ),
    ]
)
