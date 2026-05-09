// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenRecorderMac",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "OpenRecorderMac",
            resources: [
                .process("Resources/OpenRecorderMenuBarIcon.png"),
                .copy("Resources/Wallpapers")
            ]
        ),
        .testTarget(
            name: "OpenRecorderMacTests",
            dependencies: ["OpenRecorderMac"]
        ),
    ]
)
