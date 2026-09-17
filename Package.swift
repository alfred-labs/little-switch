// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LittleSwitch",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LittleSwitchWire", targets: ["LittleSwitchWire"]),
        .library(name: "LittleSwitchTransport", targets: ["LittleSwitchTransport"]),
        .library(name: "LittleSwitchSearch", targets: ["LittleSwitchSearch"]),
        .library(name: "LittleSwitchCore", targets: ["LittleSwitchCore"]),
        .library(name: "LittleSwitchUI", targets: ["LittleSwitchUI"]),
        .executable(name: "LittleSwitch", targets: ["LittleSwitch"]),
        .executable(name: "LittleSwitchUITestHost", targets: ["LittleSwitchUITestHost"]),
    ],
    dependencies: [
        .package(path: "Vendor/OrderedJSON"),
        .package(
            url: "https://github.com/LebJe/TOMLKit.git",
            exact: "0.5.0"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        ),
        .package(
            url: "https://github.com/facebook/zstd.git",
            exact: "1.5.7"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            exact: "2.26.0"
        ),
        .package(
            url: "https://github.com/swift-server/async-http-client.git",
            exact: "1.36.0"
        ),
        .package(
            url: "https://github.com/swift-server/swift-service-lifecycle.git",
            exact: "2.12.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio.git",
            exact: "2.101.3"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-http2.git",
            exact: "1.45.0"
        ),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.2"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.15.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.1"),
        .package(
            url: "https://github.com/apple/swift-http-types.git",
            exact: "1.6.0"
        ),
        .package(
            url: "https://github.com/apple/swift-certificates.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-asn1.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            exact: "2.9.6"
        ),
    ],
    targets: [
        .target(name: "LittleSwitchCommon"),
        .target(
            name: "LittleSwitchWire",
            dependencies: [.product(name: "OrderedJSON", package: "orderedjson")]
        ),
        .target(
            name: "LittleSwitchTransport",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "libzstd", package: "zstd"),
            ]
        ),
        .target(
            name: "LittleSwitchSearch",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchTransport",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .target(
            name: "LittleSwitchCore",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchWire",
                "LittleSwitchTransport",
                "LittleSwitchSearch",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdCore", package: "hummingbird"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "LittleSwitchUI",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchCore",
                "LittleSwitchTransport",
                "LittleSwitchSearch",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LittleSwitch",
            dependencies: ["LittleSwitchCore", "LittleSwitchUI"]
        ),
        .executableTarget(
            name: "LittleSwitchUITestHost",
            path: "Tools/LittleSwitchUITestHost"
        ),
        .testTarget(
            name: "LittleSwitchCommonTests",
            dependencies: ["LittleSwitchCommon"]
        ),
        .testTarget(
            name: "LittleSwitchWireTests",
            dependencies: ["LittleSwitchWire", "LittleSwitchWireContractFixtures"],
            exclude: ["Generated"]
        ),
        .target(
            name: "LittleSwitchWireContractFixtures",
            dependencies: ["LittleSwitchWire"],
            path: "Tests/LittleSwitchWireTests/Generated"
        ),
        .testTarget(
            name: "LittleSwitchTransportTests",
            dependencies: [
                "LittleSwitchTransport",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "libzstd", package: "zstd"),
            ]
        ),
        .testTarget(
            name: "LittleSwitchSearchTests",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchSearch",
                "LittleSwitchTransport",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "LittleSwitchCoreTests",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchWire",
                "LittleSwitchCore",
                "LittleSwitchTransport",
                "LittleSwitchSearch",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "libzstd", package: "zstd"),
            ]
        ),
        .testTarget(
            name: "LittleSwitchUITests",
            dependencies: [
                "LittleSwitchCommon",
                "LittleSwitchCore",
                "LittleSwitchUI",
                "LittleSwitchTransport",
                "LittleSwitchSearch",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
