import Foundation

enum CoverageReportRows {
    private struct Row {
        let lineIndex: Int
        let fields: [Substring]
    }

    static func fields(sources: [String], layouts: [[String]], lines: [String]) throws -> [[Substring]] {
        let matches = layouts.map { layout in layout.map { rows(named: $0, in: lines) } }
        var selected = matches[0]
        for candidate in matches.dropFirst() where score(candidate) > score(selected) {
            selected = candidate
        }
        // Choose one layout for the whole report. An alias from one source must
        // never satisfy another source in a different relative-path layout.
        var assignedLines = Set<Int>()
        var fields: [[Substring]] = []
        for (index, rows) in selected.enumerated() {
            let expected = CoverageReportPaths.relativeSource(sources[index])
            guard !rows.isEmpty else { throw CoverageValidationError("Missing coverage row: \(expected)") }
            guard rows.count == 1 else { throw CoverageValidationError("Duplicate coverage rows: \(expected)") }
            guard assignedLines.insert(rows[0].lineIndex).inserted else {
                throw CoverageValidationError("Coverage row assigned to multiple sources: \(expected)")
            }
            fields.append(rows[0].fields)
        }
        for (index, source) in sources.enumerated() {
            let extraRows = matches.flatMap { $0[index] }.filter { !assignedLines.contains($0.lineIndex) }
            guard extraRows.isEmpty else {
                throw CoverageValidationError("Duplicate coverage rows: \(CoverageReportPaths.relativeSource(source))")
            }
        }
        for (index, line) in lines.enumerated()
        where !assignedLines.contains(index) && line.firstMatch(of: /\.swift(?:\s|$)/) != nil {
            throw CoverageValidationError("Unexpected Swift source row in measured coverage: \(line)")
        }
        return fields
    }

    private static func score(_ rows: [[Row]]) -> Int {
        rows.filter { !$0.isEmpty }.count
    }

    private static func rows(named name: String, in lines: [String]) -> [Row] {
        lines.enumerated().compactMap { index, line in
            guard line.utf8.starts(with: name.utf8) else { return nil }
            let remainder = String(line.unicodeScalars.dropFirst(name.unicodeScalars.count))
            guard remainder.firstMatch(of: /^\s+[0-9]+\s+/) != nil else { return nil }
            return Row(lineIndex: index, fields: remainder.split(whereSeparator: \.isWhitespace))
        }
    }
}
