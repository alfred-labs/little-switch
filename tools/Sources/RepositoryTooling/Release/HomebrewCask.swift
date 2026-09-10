import Foundation

package enum HomebrewCask {
    package static func validateArtifactName(_ name: String, version: String) throws {
        guard name == "LittleSwitch-\(version)-arm64.dmg" else {
            throw ReleaseValidationError("DMG filename does not match the requested release version")
        }
    }

    package static func update(_ source: String, version: String, checksum: String) throws -> String {
        let requested = try MarketingVersion(version)
        guard checksum.wholeMatch(of: #/[a-f0-9]{64}/#) != nil else {
            throw ReleaseValidationError("Invalid DMG SHA-256")
        }
        let lines = source.components(separatedBy: "\n")
        let normalized = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard normalized.contains("cask \"littleswitch\" do") else {
            throw ReleaseValidationError("Expected the LittleSwitch cask")
        }
        let urls = fields("url", in: normalized)
        let template =
            "https://github.com/alfred-labs/little-switch/releases/download/v#{version}/LittleSwitch-#{version}-arm64.dmg"
        guard urls.count == 1, urls.first?.value == template else {
            throw ReleaseValidationError("Homebrew download URL must use the canonical versioned DMG template")
        }
        let versions = fields("version", in: normalized)
        let checksums = fields("sha256", in: normalized)
        guard versions.count == 1, let currentVersion = versions.first,
            checksums.count == 1, let currentChecksum = checksums.first,
            currentChecksum.value.wholeMatch(of: #/[a-f0-9]{64}/#) != nil
        else {
            throw ReleaseValidationError("Expected one literal version and one SHA-256 in the cask")
        }
        let current = try MarketingVersion(currentVersion.value)
        guard requested >= current else { throw ReleaseValidationError("Refusing to downgrade the Homebrew cask") }
        guard requested != current || currentChecksum.value == checksum else {
            throw ReleaseValidationError("Published DMGs are immutable: use a new version for a different SHA-256")
        }
        var updated = lines
        updated[currentVersion.row] = lines[currentVersion.row].replacingOccurrences(
            of: currentVersion.value, with: version)
        updated[currentChecksum.row] = lines[currentChecksum.row].replacingOccurrences(
            of: currentChecksum.value, with: checksum)
        return updated.joined(separator: "\n")
    }

    private static func fields(_ name: String, in lines: [String]) -> [(row: Int, value: String)] {
        let prefix = "  \(name) \""
        return lines.enumerated().compactMap { row, line in
            guard line.hasPrefix(prefix), line.hasSuffix("\"") else { return nil }
            return (row, String(line.dropFirst(prefix.count).dropLast()))
        }
    }
}
