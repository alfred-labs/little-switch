// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OrderedJSON",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OrderedJSON", targets: ["OrderedJSON"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.6.0"),
    ],
    targets: [
        .target(
            name: "OrderedJSON",
            dependencies: [.product(name: "OrderedCollections", package: "swift-collections")]
        ),
        .testTarget(
            name: "OrderedJSONTests",
            dependencies: [
                "OrderedJSON", .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            resources: [.copy("JSONTestSuite")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
