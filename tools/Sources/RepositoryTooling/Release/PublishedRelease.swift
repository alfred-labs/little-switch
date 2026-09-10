import Foundation

package enum PublishedRelease {
    package static func verify(_ metadata: Data, version: String, checksum: String, size: UInt64) throws {
        let release = try JSONDecoder().decode(Metadata.self, from: metadata)
        guard release.tagName == "v\(version)", !release.draft, !release.prerelease else {
            throw ReleaseValidationError("Homebrew requires the matching public, stable GitHub release")
        }
        let assets = release.assets?.filter { $0.name == "LittleSwitch-\(version)-arm64.dmg" } ?? []
        guard assets.count == 1, let asset = assets.first else {
            throw ReleaseValidationError("Expected exactly one published LittleSwitch DMG")
        }
        guard asset.digest == "sha256:\(checksum)", asset.size == size else {
            throw ReleaseValidationError("Published DMG SHA-256 or size differs from the local notarized artifact")
        }
        guard asset.browserDownloadURL == SparkleAppcast.enclosureURL(version: version) else {
            throw ReleaseValidationError("Published DMG URL does not match the Homebrew cask release URL")
        }
    }
}

private struct Metadata: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }
}

private struct Asset: Decodable {
    let name: String
    let digest: String?
    let size: UInt64
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name, digest, size
        case browserDownloadURL = "browser_download_url"
    }
}
