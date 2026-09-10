import Foundation

package enum CoverageReport {
    package static func validate(measuredSources: [String], report: String, rootPath: String? = nil) throws {
        guard let firstSource = measuredSources.first else {
            throw CoverageValidationError("Coverage scope classifier returned no measured Swift sources")
        }
        guard Set(measuredSources).count == measuredSources.count else {
            throw CoverageValidationError("Coverage scope classifier returned a duplicate measured source")
        }
        try rejectWarnings(report, label: "Measured coverage")
        let lines = report.components(separatedBy: "\n")
        let commonDirectory = CoverageReportPaths.commonDirectory(
            first: firstSource, remaining: measuredSources.dropFirst())
        for source in measuredSources {
            try CoverageSourcePath.validate(source, location: "measured coverage scope")
        }
        let layouts = CoverageReportPaths.layouts(
            sources: measuredSources, commonDirectory: commonDirectory, rootPath: rootPath)
        let rows = try CoverageReportRows.fields(sources: measuredSources, layouts: layouts, lines: lines)
        var measuredLines: UInt64 = 0
        for (source, fields) in zip(measuredSources, rows) {
            let count = try requireExact(fields, label: CoverageReportPaths.relativeSource(source))
            let (sum, overflow) = measuredLines.addingReportingOverflow(count)
            guard !overflow else { throw CoverageValidationError("Measured line count overflow") }
            measuredLines = sum
        }
        let total = try totalRow(lines, label: "measured coverage")
        let totalLines = try requireExact(Array(total.dropFirst()), label: "Measured TOTAL")
        guard totalLines == measuredLines else {
            throw CoverageValidationError("Measured TOTAL line count differs from the measured source sum")
        }
    }

    package static func validateRaw(_ report: String) throws {
        try rejectWarnings(report, label: "Raw linked-source coverage")
        _ = try totalRow(report.components(separatedBy: "\n"), label: "raw linked-source coverage")
    }

    private static func rejectWarnings(_ report: String, label: String) throws {
        guard report.firstMatch(of: /(?:^|\s)warning:/.ignoresCase()) == nil else {
            throw CoverageValidationError("\(label) report contains an llvm-cov warning")
        }
    }

    private static func totalRow(_ lines: [String], label: String) throws -> [Substring] {
        let totals = lines.map { $0.split(whereSeparator: \.isWhitespace) }.filter { $0.first == "TOTAL" }
        guard !totals.isEmpty else {
            throw CoverageValidationError("Missing \(label) TOTAL row")
        }
        guard totals.count == 1 else {
            throw CoverageValidationError("Duplicate \(label) TOTAL rows")
        }
        return totals[0]
    }

    private static func requireExact(_ fields: [Substring], label: String) throws -> UInt64 {
        let percentage = fields.count >= 9 ? String(fields[8]) : ""
        guard percentage == "100.00%" else {
            throw CoverageValidationError("\(label) line coverage must be exactly 100.00%; got \(percentage)")
        }
        guard fields.count == 9 || fields.count == 12,
            fields[6].utf8.allSatisfy({ (48...57).contains($0) }),
            fields[7].utf8.allSatisfy({ (48...57).contains($0) }),
            let count = UInt64(fields[6]), count > 0,
            let missed = UInt64(fields[7]), missed == 0
        else {
            throw CoverageValidationError("\(label) must have valid positive line counts and zero missed lines")
        }
        return count
    }
}
