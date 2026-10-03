// swift-tools-version:5.9
// The Xcode project (AmbientScreenIntelligence.xcodeproj) builds the macOS app.
// This package exposes the platform-independent core logic so it can be
// unit-tested with `swift test` (on macOS, and on Linux CI as well).
import PackageDescription

let package = Package(
    name: "AmbientScreenIntelligence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AmbientCore", targets: ["AmbientCore"])
    ],
    targets: [
        .target(name: "AmbientCore", path: "Sources/AmbientCore"),
        .testTarget(name: "AmbientCoreTests", dependencies: ["AmbientCore"], path: "Tests/AmbientCoreTests")
    ]
)
