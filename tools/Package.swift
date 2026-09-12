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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "RepositoryTooling",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
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
