import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Coverage report validation")
struct CoverageReportTests {
    @Test("A filename with report-like columns cannot impersonate another source")
    func numericFilenamePrefix() {
        let name = "App/A.swift 1 0 100.00% 1 0 100.00% 1 0 100.00% /B.swift"
        let report = CoverageFixture.report([(name, "100.00%")])
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift", "Sources/" + name], report: report)
        }
    }

    @Test("Measured reports reject extra Swift sources even if TOTAL omits them")
    func unexpectedSource() {
        let report = CoverageFixture.report() + "App/Unexpected.swift 1 0 100.00% 1 0 100.00% 1 0 100.00%\n"
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: report)
        }
    }

    @Test("A rounded percentage cannot hide an uncovered line", arguments: [false, true])
    func roundedCoverage(totalOnly: Bool) {
        let file = "App/A.swift 1 0 100.00% 1 0 100.00% 100000 \(totalOnly ? 0 : 1) 100.00%\n"
        let total = "TOTAL 1 0 100.00% 1 0 100.00% 100000 1 100.00%\n"
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: file + total)
        }
    }

    @Test(
        "Line counters must be positive unsigned integers with no missed lines",
        arguments: [
            ("0", "0"), ("-1", "0"), ("+1", "0"), ("word", "0"),
            ("18446744073709551616", "0"), ("1", "-1"), ("1", "+0"), ("1", "word"),
        ])
    func invalidCounters(count: String, missed: String) {
        let report =
            "App/A.swift 1 0 100.00% 1 0 100.00% \(count) \(missed) 100.00%\n"
            + "TOTAL 1 0 100.00% 1 0 100.00% 1 0 100.00%\n"
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: report)
        }
    }

    @Test("Measured TOTAL equals the sum of the actual measured line counts")
    func inconsistentTotal() {
        let report =
            "App/A.swift 1 0 100.00% 1 0 100.00% 3 0 100.00%\n"
            + "TOTAL 1 0 100.00% 1 0 100.00% 4 0 100.00%\n"
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: report)
        }
    }

    @Test("Overflowing synthetic totals are rejected without trapping")
    func counterOverflow() {
        let report =
            "App/A.swift 1 0 100.00% 1 0 100.00% 18446744073709551615 0 100.00%\n"
            + "App/B.swift 1 0 100.00% 1 0 100.00% 1 0 100.00%\n"
            + "TOTAL 1 0 100.00% 1 0 100.00% 18446744073709551615 0 100.00%\n"
        #expect(throws: CoverageValidationError.self) {
            try CoverageReport.validate(
                measuredSources: ["Sources/App/A.swift", "Sources/App/B.swift"], report: report)
        }
    }

    @Test("Every measured row and total must report exactly 100.00 percent lines")
    func exact() throws {
        let sources = ["Sources/App/A name.swift", "Sources/Z/Z.swift"]
        let report = CoverageFixture.report([("App/A name.swift", "100.00%"), ("Z/Z.swift", "100.00%")])
        try CoverageReport.validate(measuredSources: sources, report: report)
        try CoverageReport.validateRaw(CoverageFixture.report(total: "0.00%"))
    }

    @Test(
        "Missing, duplicate and imprecise measured coverage are rejected",
        arguments: [
            ("", "Missing coverage row: App/A.swift"),
            (CoverageFixture.report([]), "Missing coverage row: App/A.swift"),
            (
                CoverageFixture.report([("App/A.swift", "100.00%"), ("App/A.swift", "100.00%")]),
                "Duplicate coverage rows"
            ),
            (CoverageFixture.report([("App/A.swift", "99.00%")]), "line coverage must be exactly 100.00%; got 99.00%"),
            (CoverageFixture.report([("App/A.swift", "100%")]), "line coverage must be exactly 100.00%; got 100%"),
            (
                CoverageFixture.report(total: "99.00%"),
                "Measured TOTAL line coverage must be exactly 100.00%; got 99.00%"
            ),
            ("App/A.swift 1 0\nTOTAL 1 0\n", "line coverage must be exactly 100.00%; got "),
            ("App/A.swiftX 1 0 100.00%\n", "Missing coverage row"),
            ("App/A.swift   words\n", "Missing coverage row"),
            ("App/A.swift", "Missing coverage row"),
            ("warning: fixture source not linked\n", "Measured coverage report contains an llvm-cov warning"),
            ("llvm-cov WARNING: fixture\n", "Measured coverage report contains an llvm-cov warning"),
        ])
    func measuredFailure(fixture: (String, String)) {
        expectCoverageFailure(fixture.1) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: fixture.0)
        }
    }

    @Test("Measured totals must occur once", arguments: [false, true])
    func measuredTotals(duplicate: Bool) {
        let total = "TOTAL 1 0 100.00% 1 0 100.00% 1 0 100.00%\n"
        let report = "App/A.swift 1 0 100.00% 1 0 100.00% 1 0 100.00%\n" + (duplicate ? total + total : "")
        expectCoverageFailure(
            duplicate ? "Duplicate measured coverage TOTAL rows" : "Missing measured coverage TOTAL row"
        ) {
            try CoverageReport.validate(measuredSources: ["Sources/App/A.swift"], report: report)
        }
    }

    @Test("Empty scope and duplicate measured paths cannot pass")
    func invalidScope() {
        expectCoverageFailure("no measured Swift sources") {
            try CoverageReport.validate(measuredSources: [], report: CoverageFixture.report())
        }
        expectCoverageFailure("duplicate measured source") {
            try CoverageReport.validate(
                measuredSources: ["Sources/App/A.swift", "Sources/App/A.swift"], report: CoverageFixture.report())
        }
        expectCoverageFailure("path is missing") {
            try CoverageReport.validate(measuredSources: [""], report: CoverageFixture.report())
        }
    }

    @Test(
        "Raw reports need a unique total and no warnings",
        arguments: [
            ("", "Missing raw linked-source coverage TOTAL row"),
            ("TOTAL 0\nTOTAL 0\n", "Duplicate raw linked-source coverage TOTAL rows"),
            (" warning: unmapped source\nTOTAL 0\n", "Raw linked-source coverage report contains an llvm-cov warning"),
        ])
    func rawFailure(fixture: (String, String)) {
        expectCoverageFailure(fixture.1) { try CoverageReport.validateRaw(fixture.0) }
    }

    @Test("Warning-like filenames do not count as diagnostics")
    func warningFilename() throws {
        try CoverageReport.validate(
            measuredSources: ["Sources/App/notwarning:Name.swift"],
            report: CoverageFixture.report([("App/notwarning:Name.swift", "100.00%")]))
    }

    @Test("LLVM can strip the measured module's common directory")
    func commonDirectory() throws {
        try CoverageReport.validate(
            measuredSources: [
                "Sources/RepositoryTooling/Coverage/A.swift", "Sources/RepositoryTooling/Repository/B.swift",
            ],
            report: CoverageFixture.report([("Coverage/A.swift", "100.00%"), ("Repository/B.swift", "100.00%")]))
    }

    @Test("Short names shared by different targets cannot satisfy either measured source")
    func ambiguousBasename() {
        expectCoverageFailure("Missing coverage row") {
            try CoverageReport.validate(
                measuredSources: ["Sources/Core/A.swift", "Sources/UI/A.swift"],
                report: CoverageFixture.report([("A.swift", "100.00%")]))
        }
    }

    @Test("Two representations of one source still count as duplicate coverage rows")
    func duplicateRepresentations() {
        expectCoverageFailure("Duplicate coverage rows") {
            try CoverageReport.validate(
                measuredSources: ["Sources/Tooling/A.swift", "Sources/Tooling/B.swift"],
                report: CoverageFixture.report([
                    ("Tooling/A.swift", "100.00%"), ("A.swift", "100.00%"), ("B.swift", "100.00%"),
                ]))
        }
    }

    @Test("The absolute path emitted for one measured source is checked against the package root")
    func absoluteRow() throws {
        try CoverageReport.validate(
            measuredSources: ["Sources/App/A.swift"],
            report: CoverageFixture.report([("/repository with spaces/Sources/App/A.swift", "100.00%")]),
            rootPath: "/repository with spaces")
        expectCoverageFailure("Missing coverage row") {
            try CoverageReport.validate(
                measuredSources: ["Sources/App/A.swift"],
                report: CoverageFixture.report([("/different/Sources/App/A.swift", "100.00%")]),
                rootPath: "/repository with spaces")
        }
    }

    @Test("A row cannot satisfy two sources through overlapping relative layouts")
    func overlappingLayouts() throws {
        let sources = ["Sources/Tools/A.swift", "Sources/Tools/Tools/A.swift"]
        expectCoverageFailure("Missing coverage row") {
            try CoverageReport.validate(
                measuredSources: sources, report: CoverageFixture.report([("Tools/A.swift", "100.00%")]))
        }
        try CoverageReport.validate(
            measuredSources: sources,
            report: CoverageFixture.report([("A.swift", "100.00%"), ("Tools/A.swift", "100.00%")]))
    }
}

func expectCoverageFailure(_ diagnostic: String, operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected failure containing: \(diagnostic)")
    } catch {
        #expect(error.localizedDescription.contains(diagnostic))
    }
}
