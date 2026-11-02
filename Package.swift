// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FunnelsGroveSDK",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "FunnelsGroveSDK", targets: ["FunnelsGroveSDK"]),
    ],
    targets: [
        .target(name: "FunnelsGroveSDK"),
        .testTarget(name: "FunnelsGroveSDKTests", dependencies: ["FunnelsGroveSDK"]),
    ]
)
