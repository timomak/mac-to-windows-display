// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ThunderMirror",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // CLI executable
        .executable(
            name: "ThunderMirror",
            targets: ["ThunderMirror"]
        ),
    ],
    dependencies: [
        // Argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Main CLI target
        .executableTarget(
            name: "ThunderMirror",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ThunderMirror"
        ),
        // Tests
        .testTarget(
            name: "ThunderMirrorTests",
            dependencies: ["ThunderMirror"],
            path: "Tests"
        ),
    ]
)
