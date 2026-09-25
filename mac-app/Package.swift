// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GcmdApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "GcmdCore", targets: ["GcmdCore"]),
        .executable(name: "gcmd-app", targets: ["GcmdApp"]),
        .executable(name: "gcmd", targets: ["GcmdCLI"])
    ],
    targets: [
        .target(
            name: "GcmdCore",
            path: "Sources/GcmdCore"
        ),
        .executableTarget(
            name: "GcmdApp",
            dependencies: ["GcmdCore"],
            path: "Sources/GcmdApp"
        ),
        .executableTarget(
            name: "GcmdCLI",
            dependencies: ["GcmdCore"],
            path: "Sources/GcmdCLI"
        ),
        .testTarget(
            name: "GcmdCoreTests",
            dependencies: ["GcmdCore"],
            path: "Tests/GcmdCoreTests"
        )
    ]
)
