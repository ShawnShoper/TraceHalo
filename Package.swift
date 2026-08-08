// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SystemScope",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SystemScopeCore", targets: ["SystemScopeCore"]),
        .executable(name: "SystemScope", targets: ["SystemScopeApp"]),
        .executable(name: "SystemScopeSensorHelper", targets: ["SystemScopeSensorHelper"])
    ],
    targets: [
        .target(
            name: "SystemScopeCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SystemScopeApp",
            dependencies: ["SystemScopeCore"],
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
            name: "SystemScopeSensorHelper",
            dependencies: ["SystemScopeCore"]
        ),
        .testTarget(
            name: "SystemScopeCoreTests",
            dependencies: ["SystemScopeCore"]
        ),
        .testTarget(
            name: "SystemScopeAppTests",
            dependencies: ["SystemScopeApp", "SystemScopeCore"]
        )
    ]
)
