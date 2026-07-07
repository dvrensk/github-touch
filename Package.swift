// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GitHubTouch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GitHubTouchCore"),
        .executableTarget(name: "GitHubTouch", dependencies: ["GitHubTouchCore"]),
        .testTarget(name: "GitHubTouchCoreTests", dependencies: ["GitHubTouchCore"]),
    ]
)
