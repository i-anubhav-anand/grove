// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorktreeKit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WorktreeKit"),
        .executableTarget(
            name: "worktree-poc",
            dependencies: ["WorktreeKit"]
        ),
    ]
)
