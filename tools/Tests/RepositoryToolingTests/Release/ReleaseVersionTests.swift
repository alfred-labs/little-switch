import Testing

@testable import RepositoryTooling

@Suite("Release version counter")
struct ReleaseVersionTests {
    @Test("Malformed metadata exposes a useful command-line diagnostic")
    func metadataDiagnostic() {
        do {
            _ = try ReleaseVersion.bump("BUILD_NUMBER=20\n")
            Issue.record("Missing version metadata must fail")
        } catch {
            #expect(error.localizedDescription == "Expected exactly one MARKETING_VERSION and one BUILD_NUMBER")
        }
    }

    @Test("The build advances independently of the marketing version and preserves other lines")
    func increment() throws {
        let source = "# Release metadata\nMARKETING_VERSION=0.4.4\nBUILD_NUMBER=15\nOTHER=value\n"
        #expect(
            try ReleaseVersion.bump(source)
                == .init(
                    contents: source.replacingOccurrences(of: "BUILD_NUMBER=15", with: "BUILD_NUMBER=16"),
                    marketing: "0.4.4",
                    build: "16"))
        #expect(
            try ReleaseVersion.bump(source, marketing: "0.5.0")
                == .init(
                    contents: "# Release metadata\nMARKETING_VERSION=0.5.0\nBUILD_NUMBER=16\nOTHER=value\n",
                    marketing: "0.5.0",
                    build: "16"))
    }

    @Test("Decimal counters do not overflow or interpret leading zeroes as octal")
    func decimalCounter() throws {
        #expect(
            try ReleaseVersion.bump("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=999999999999999999999\n").build
                == "1000000000000000000000")
        #expect(try ReleaseVersion.bump("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=009\n").build == "10")
        #expect(try ReleaseVersion.bump("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=0").build == "1")
    }

    @Test(
        "Equal and increasing marketing versions preserve monotonic builds",
        arguments: ["1.2.3", "1.2.4", "1.10.0", "2.0.0", "999999999999999999999.0.0"])
    func acceptedVersion(marketing: String) throws {
        #expect(
            try ReleaseVersion.bump("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=20\n", marketing: marketing).marketing
                == marketing)
    }

    @Test(
        "Invalid, multiline and decreasing marketing versions fail",
        arguments: [
            "", "1.2", "v1.2.3", "1.2.3.4", "1.2.-3", "1.2.3\nBUILD_NUMBER=1", "1.2.3\r", "1.2.2", "1.1.9", "0.9.9",
        ])
    func rejectedVersion(marketing: String) {
        #expect(throws: ReleaseValidationError.self) {
            try ReleaseVersion.bump("MARKETING_VERSION=1.2.3\nBUILD_NUMBER=20\n", marketing: marketing)
        }
    }

    @Test(
        "Missing, ambiguous and malformed metadata is rejected",
        arguments: [
            "MARKETING_VERSION=1.2.3\n", "BUILD_NUMBER=20\n", "MARKETING_VERSION=\nBUILD_NUMBER=20\n",
            "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=\n", "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=1.2\n",
            "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=-1\n", "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=20\nBUILD_NUMBER=21\n",
            "MARKETING_VERSION=1.2.3\nMARKETING_VERSION=1.2.4\nBUILD_NUMBER=20\n",
        ])
    func invalidMetadata(source: String) {
        #expect(throws: ReleaseValidationError.self) { try ReleaseVersion.bump(source) }
    }
}
