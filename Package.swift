// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TraceHalo",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TraceHaloCore", targets: ["TraceHaloCore"]),
        .executable(name: "TraceHalo", targets: ["TraceHaloApp"]),
        .executable(name: "TraceHaloSensorHelper", targets: ["TraceHaloSensorHelper"])
    ],
    targets: [
        .target(
            name: "TraceHaloCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TraceHaloApp",
            dependencies: ["TraceHaloCore"],
            exclude: [
                "Resources/mac-studio-center-chroma.png",
                "Resources/mac-studio-center.png",
                "Resources/mac-studio-dashboard.png",
                "Resources/mac-studio-dashboard-cropped.png"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TraceHaloSensorHelper",
            dependencies: ["TraceHaloCore"]
        ),
        .testTarget(
            name: "TraceHaloCoreTests",
            dependencies: ["TraceHaloCore"]
        ),
        .testTarget(
            name: "TraceHaloAppTests",
            dependencies: ["TraceHaloApp", "TraceHaloCore"]
        )
    ]
)
