// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftWhisper",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SwiftWhisperCore", targets: ["SwiftWhisperCore"]),
        .library(name: "SwiftWhisperPlatform", targets: ["SwiftWhisperPlatform"]),
        .executable(name: "SwiftWhisperApp", targets: ["SwiftWhisperApp"]),
    ],
    targets: [
        .target(name: "SwiftWhisperCore"),
        .target(
            name: "SwiftWhisperPlatform",
            dependencies: ["SwiftWhisperCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
            ]
        ),
        .executableTarget(
            name: "SwiftWhisperApp",
            dependencies: ["SwiftWhisperCore", "SwiftWhisperPlatform"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "SwiftWhisperCoreTests",
            dependencies: ["SwiftWhisperCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
