import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Homebrew release cask")
struct HomebrewCaskTests {
    struct RejectedUpdate: Sendable {
        let version: String
        let checksum: String
        let diagnostic: String
    }

    static let checksum = String(repeating: "0", count: 64)
    static let source = """
        cask "littleswitch" do
          version "1.2.2"
          sha256 "\(checksum)"

          url "https://github.com/alfred-labs/little-switch/releases/download/v#{version}/LittleSwitch-#{version}-arm64.dmg"
          name "LittleSwitch"
          app "LittleSwitch.app"
        end

        """

    @Test("Only literal version and checksum fields change and CRLF survives")
    func update() throws {
        let checksum = String(repeating: "f", count: 64)
        for source in [Self.source, Self.source.replacingOccurrences(of: "\n", with: "\r\n")] {
            #expect(
                try HomebrewCask.update(source, version: "1.2.3", checksum: checksum)
                    == source.replacingOccurrences(of: "version \"1.2.2\"", with: "version \"1.2.3\"")
                    .replacingOccurrences(of: Self.checksum, with: checksum))
        }
        #expect(try HomebrewCask.update(Self.source, version: "1.2.2", checksum: Self.checksum) == Self.source)
        #expect(
            try HomebrewCask.update(Self.source, version: "999999999999999999999.0.0", checksum: checksum).contains(
                "999999999999999999999.0.0"))
    }

    @Test(
        "Malformed or mutable releases are refused",
        arguments: [
            RejectedUpdate(version: "1.2.1", checksum: checksum, diagnostic: "downgrade"),
            RejectedUpdate(version: "1.2.2", checksum: String(repeating: "f", count: 64), diagnostic: "immutable"),
            RejectedUpdate(version: "1.2.3\ninjected", checksum: checksum, diagnostic: "numeric"),
            RejectedUpdate(version: "1.2.3", checksum: "ABC", diagnostic: "SHA-256"),
        ])
    func invalid(value: RejectedUpdate) {
        do {
            _ = try HomebrewCask.update(Self.source, version: value.version, checksum: value.checksum)
            Issue.record("Invalid cask update must fail")
        } catch {
            #expect(error.localizedDescription.contains(value.diagnostic))
        }
    }

    @Test("Cask identity and ambiguous or pinned fields fail closed")
    func malformedCask() {
        let invalid = [
            Self.source.replacingOccurrences(of: "cask \"littleswitch\"", with: "cask \"another-app\""),
            Self.source.replacingOccurrences(of: "#{version}", with: "1.2.2"),
            Self.source.replacingOccurrences(
                of: "  version \"1.2.2\"", with: "  version \"1.2.2\"\n  version \"1.2.1\""),
            Self.source.replacingOccurrences(of: "  sha256", with: "  sha257"),
        ]
        for source in invalid {
            #expect(throws: ReleaseValidationError.self) {
                try HomebrewCask.update(source, version: "1.2.3", checksum: Self.checksum)
            }
        }
    }
}
