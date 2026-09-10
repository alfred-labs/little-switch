import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Published release verification")
struct PublishedReleaseTests {
    static func metadata(
        overrides: [String: Any] = [:],
        assetOverrides: [String: Any] = [:],
        duplicate: Bool = false
    ) throws -> Data {
        let asset: [String: Any] = [
            "name": "LittleSwitch-1.2.3-arm64.dmg", "digest": "sha256:" + HomebrewCaskTests.checksum, "size": 42,
            "browser_download_url":
                "https://github.com/alfred-labs/little-switch/releases/download/v1.2.3/LittleSwitch-1.2.3-arm64.dmg",
        ].merging(assetOverrides) { _, new in new }
        let release: [String: Any] = [
            "tag_name": "v1.2.3", "draft": false, "prerelease": false, "assets": duplicate ? [asset, asset] : [asset],
        ]
        .merging(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: release, options: .sortedKeys)
    }

    @Test("One public stable canonical artifact must match all local release facts")
    func release() throws {
        try PublishedRelease.verify(Self.metadata(), version: "1.2.3", checksum: HomebrewCaskTests.checksum, size: 42)
        let invalid = try [
            Self.metadata(overrides: ["draft": true]), Self.metadata(overrides: ["prerelease": true]),
            Self.metadata(overrides: ["tag_name": "v9.0.0"]), Self.metadata(overrides: ["assets": []]),
            Self.metadata(overrides: ["assets": NSNull()]),
            Self.metadata(duplicate: true), Self.metadata(assetOverrides: ["size": 43]),
            Self.metadata(assetOverrides: ["digest": "sha256:invalid"]),
            Self.metadata(assetOverrides: ["browser_download_url": "https://example.invalid/app.dmg"]),
            Self.metadata(assetOverrides: ["name": "other.dmg"]), Data("not json".utf8),
        ]
        for metadata in invalid {
            #expect(throws: (any Error).self) {
                try PublishedRelease.verify(metadata, version: "1.2.3", checksum: HomebrewCaskTests.checksum, size: 42)
            }
        }
    }
}
