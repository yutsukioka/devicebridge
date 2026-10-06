// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DeviceBridgeCore", targets: ["DeviceBridgeCore"]),
        .executable(name: "DeviceBridge", targets: ["DeviceBridgeApp"]),
        .executable(name: "devicebridge-fixtures", targets: ["DeviceBridgeFixtures"])
    ],
    targets: [
        .target(name: "DeviceBridgeCore"),
        .executableTarget(name: "DeviceBridgeApp", dependencies: ["DeviceBridgeCore"]),
        .executableTarget(name: "DeviceBridgeFixtures", dependencies: ["DeviceBridgeCore"]),
        .testTarget(name: "DeviceBridgeCoreTests", dependencies: ["DeviceBridgeCore"])
    ]
)
