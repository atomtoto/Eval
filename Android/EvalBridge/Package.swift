// swift-tools-version: 6.1
// The bridge between EvalCore and the Android app, built with Skip Fuse (https://skip.dev).
// Kept apart from the root package so that Xcode never resolves the Skip dependencies.
import Foundation
import PackageDescription

// The repository root, which holds EvalCore. It is found through Sources: for Gradle,
// Skip copies this manifest into its build folder and links Sources back here.
let repository = URL(fileURLWithPath: Context.packageDirectory)
    .appendingPathComponent("Sources").resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let package = Package(
    name: "eval-bridge",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EvalBridge", type: .dynamic, targets: ["EvalBridge"])
    ],
    dependencies: [
        .package(path: repository.path),
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse.git", from: "1.0.0")
    ],
    targets: [
        .target(name: "EvalBridge", dependencies: [
            .product(name: "EvalCore", package: repository.lastPathComponent),
            .product(name: "SkipFuse", package: "skip-fuse")
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "EvalBridgeTests", dependencies: [
            "EvalBridge",
            .product(name: "SkipTest", package: "skip")
        ], plugins: [.plugin(name: "skipstone", package: "skip")])
    ]
)
