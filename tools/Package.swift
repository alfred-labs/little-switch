// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LittleSwitchTooling",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RepositoryTooling", targets: ["RepositoryTooling"]),
        .executable(name: "littleswitch-tools", targets: ["LittleSwitchTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0")
    ],
    targets: [
        .target(name: "RepositoryTooling"),
        .executableTarget(
            name: "LittleSwitchTools",
            dependencies: [
                "RepositoryTooling",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RepositoryToolingTests",
            dependencies: ["RepositoryTooling"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
