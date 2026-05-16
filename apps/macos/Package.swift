// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenRecorderMac",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "OpenRecorderMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
