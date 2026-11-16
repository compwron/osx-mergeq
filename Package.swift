// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MergeQ",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MergeQCore"),
        .executableTarget(name: "MergeQ", dependencies: ["MergeQCore"]),
        .testTarget(name: "MergeQCoreTests", dependencies: ["MergeQCore"]),
    ]
)
