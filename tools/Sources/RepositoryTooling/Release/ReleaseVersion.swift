import Foundation

package enum ReleaseVersion {
    package struct Update: Equatable, Sendable {
        package let contents: String
        package let marketing: String
        package let build: String
    }

    package static func bump(_ contents: String, marketing: String? = nil) throws -> Update {
        var lines = contents.components(separatedBy: "\n")
        let versionRows = lines.indices.filter { lines[$0].hasPrefix("MARKETING_VERSION=") }
        let buildRows = lines.indices.filter { lines[$0].hasPrefix("BUILD_NUMBER=") }
        guard versionRows.count == 1, buildRows.count == 1,
            let versionRow = versionRows.first, let buildRow = buildRows.first
        else {
            throw ReleaseValidationError("Expected exactly one MARKETING_VERSION and one BUILD_NUMBER")
        }
        let currentMarketing = String(lines[versionRow].dropFirst("MARKETING_VERSION=".count))
        let current = try MarketingVersion(currentMarketing)
        let requested = try MarketingVersion(marketing ?? currentMarketing)
        guard requested >= current else {
            throw ReleaseValidationError("Marketing version must not sit below the current \(currentMarketing)")
        }
        let currentBuild = String(lines[buildRow].dropFirst("BUILD_NUMBER=".count))
        guard !currentBuild.isEmpty, currentBuild.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ReleaseValidationError("BUILD_NUMBER must be a plain integer")
        }
        let newBuild = increment(currentBuild)
        let newMarketing = marketing ?? currentMarketing
        lines[versionRow] = "MARKETING_VERSION=\(newMarketing)"
        lines[buildRow] = "BUILD_NUMBER=\(newBuild)"
        return Update(contents: lines.joined(separator: "\n"), marketing: newMarketing, build: newBuild)
    }

    private static func increment(_ value: String) -> String {
        var digits = Array(value.utf8.drop { $0 == 48 })
        for index in digits.indices.reversed() {
            if digits[index] < 57 {
                digits[index] += 1
                return String(digits.map { Character(UnicodeScalar($0)) })
            }
            digits[index] = 48
        }
        return "1" + String(digits.map { Character(UnicodeScalar($0)) })
    }
}
