// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BadKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BadKit", targets: ["BadKit"]),
    ],
    targets: [
        .target(name: "BadKit"),
        .testTarget(name: "BadKitTests", dependencies: ["BadKit"]),
    ]
)
