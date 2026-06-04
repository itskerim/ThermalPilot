// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FanUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FanUsage", targets: ["FanUsageApp"]),
        .library(name: "FanUsageCore", targets: ["FanUsageCore"])
    ],
    targets: [
        .target(
            name: "FanUsageCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "FanUsageApp",
            dependencies: ["FanUsageCore"]
        ),
        .testTarget(
            name: "FanUsageCoreTests",
            dependencies: ["FanUsageCore"]
        )
    ]
)
