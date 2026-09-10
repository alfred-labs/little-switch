import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Coverage exclusion manifest")
struct CoverageManifestTests {
    @Test("Blank lines and CRLF are accepted while rationale and path spaces are preserved")
    func valid() throws {
        let contents = "\r\nSources/Z/Z.swift\t native boundary \r\nSources/A/A name.swift\tprocess boundary\n"
        #expect(
            try CoverageExclusionManifest.parse(contents, path: "ci/scope.tsv") == [
                .init(path: "Sources/A/A name.swift", rationale: "process boundary"),
                .init(path: "Sources/Z/Z.swift", rationale: " native boundary "),
            ])
        #expect(try CoverageExclusionManifest.parse("", path: "empty.tsv").isEmpty)
    }

    @Test("Rationale whitespace keeps the JavaScript trim contract")
    func rationaleWhitespace() throws {
        expectCoverageFailure("rationale must not be empty") {
            _ = try CoverageExclusionManifest.parse("Sources/App/A.swift\t\u{FEFF}", path: "scope.tsv")
        }
        #expect(
            try CoverageExclusionManifest.parse("Sources/App/A.swift\t\u{0085}", path: "scope.tsv") == [
                .init(path: "Sources/App/A.swift", rationale: "\u{0085}")
            ])
    }

    @Test("Combining scalars in source filenames preserve literal path prefixes")
    func scalarPaths() throws {
        #expect(
            try CoverageExclusionManifest.parse("Sources/\u{0301}A.swift\tnative boundary", path: "scope.tsv") == [
                .init(path: "Sources/\u{0301}A.swift", rationale: "native boundary")
            ])
    }

    @Test(
        "Malformed exclusions identify the manifest line and reason",
        arguments: [
            ("\tnative boundary", "path is missing"),
            ("Sources/App/A.swift\tnative\textra", "exactly two fields"),
            ("Sources/App/A.swift", "exactly two fields"),
            ("Sources/App/A.swift\t", "rationale must not be empty"),
            ("Sources/App/A.swift\t  ", "rationale must not be empty"),
            ("Sources/App/A.swift\tnative\rcorrupt", "rationale contains a control character"),
            ("Sources\\App\\A.swift\tnative", "forward slashes"),
            ("/Sources/App/A.swift\tnative", "must not be absolute"),
            ("C:/Sources/App/A.swift\tnative", "must not be absolute"),
            ("Sources/App/*.swift\tnative", "wildcard"),
            ("Sources/App/A?.swift\tnative", "wildcard"),
            ("Sources/App/[A].swift\tnative", "wildcard"),
            ("Sources/App/{A}.swift\tnative", "wildcard"),
            ("Sources/../A.swift\tnative", "path traversal"),
            ("./Sources/App/A.swift\tnative", "must be normalized"),
            ("Sources//App/A.swift\tnative", "must be normalized"),
            ("Sources/./App/A.swift\tnative", "must be normalized"),
            ("Tests/App/A.swift\tnative", "under Sources/"),
            ("Sources/App/A.txt\tnative", "name a .swift source"),
            ("Sources/App/A\r.swift\tnative", "control character"),
            ("Sources/App/A\u{0001}.swift\tnative", "control character"),
            ("Sources/App/A.swift\tfirst\nSources/App/A.swift\tsecond", "duplicate exclusion path"),
        ])
    func invalid(fixture: (String, String)) {
        do {
            _ = try CoverageExclusionManifest.parse("\n" + fixture.0, path: "ci/scope.tsv")
            Issue.record("Expected malformed exclusion to fail: \(fixture.1)")
        } catch {
            #expect(error.localizedDescription.contains("ci/scope.tsv:"))
            #expect(error.localizedDescription.contains(fixture.1))
        }
    }
}
