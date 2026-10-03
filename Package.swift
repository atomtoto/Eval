// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EvalCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EvalCore", targets: ["EvalCore"])
    ],
    targets: [
        .target(name: "EvalCore"),
        .testTarget(name: "EvalCoreTests", dependencies: ["EvalCore"])
    ]
)
