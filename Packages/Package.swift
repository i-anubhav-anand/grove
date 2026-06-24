// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GrovePackages",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GroveCore", targets: ["GroveCore"]),
        .library(name: "GroveChatKit", targets: ["GroveChatKit"]),
    ],
    targets: [
        .target(
            name: "GroveCore",
            path: "Sources/GroveCore"
        ),
        .target(
            name: "GroveChatKit",
            dependencies: ["GroveCore"],
            path: "Sources/GroveChatKit",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "GroveCoreTests",
            dependencies: ["GroveCore"],
            path: "Tests/GroveCoreTests"
        ),
    ]
)
