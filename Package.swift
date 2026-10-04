// swift-tools-version:5.9
// The Xcode project (AmbientScreenIntelligence.xcodeproj) builds the macOS app.
// This package exposes the platform-independent core logic (all platforms) and
// the SQLite store (macOS only: GRDB does not support Linux) so they can be
// unit-tested with `swift test`.
import PackageDescription

var products: [Product] = [.library(name: "AmbientCore", targets: ["AmbientCore"])]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "AmbientCore", path: "Sources/AmbientCore"),
    .testTarget(name: "AmbientCoreTests", dependencies: ["AmbientCore"], path: "Tests/AmbientCoreTests")
]

#if os(macOS)
products.append(.library(name: "AmbientStore", targets: ["AmbientStore"]))
dependencies.append(.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"))
targets += [
    .target(
        name: "AmbientStore",
        dependencies: ["AmbientCore", .product(name: "GRDB", package: "GRDB.swift")],
        path: "Sources/AmbientStore"
    ),
    .testTarget(name: "AmbientStoreTests", dependencies: ["AmbientStore"], path: "Tests/AmbientStoreTests")
]
#endif

let package = Package(
    name: "AmbientScreenIntelligence",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
