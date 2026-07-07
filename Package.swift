// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PushEngage",
    platforms: [.iOS(.v12)],
    products: [
        .library(
            name: "PushEngageExtension",
            targets: ["PushEngageExtension"]),
        .library(
            name: "PushEngage",
            targets: ["PushEngage"]),
    ],
    targets: [
        .target(
            name: "PushEngageExtension",
            path: "Sources/PushEngageExtension"),
        .target(
            name: "PushEngage",
            dependencies: ["PushEngageExtension"],
            path: "Sources/PushEngage"),
        .testTarget(
            name: "PushEngageTests",
            dependencies: ["PushEngage", "PushEngageExtension"],
            path: "Tests/PushEngageTests"),
    ]
)
