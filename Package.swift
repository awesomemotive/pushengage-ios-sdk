// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PushEngage",
    platforms: [.iOS(.v12)],
    products: [
        .library(
            name: "PushEngage",
            targets: ["PushEngage"]),
    ],
    targets: [
        .target(
            name: "PushEngage", path: "Sources"),
        .testTarget(
            name: "PushEngageTests",
            dependencies: ["PushEngage"],
            path: "Tests/PushEngageTests"),
    ]
)
