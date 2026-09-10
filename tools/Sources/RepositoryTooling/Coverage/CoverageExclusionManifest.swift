import Foundation

package struct CoverageExclusion: Equatable, Sendable {
    package let path: String
    package let rationale: String
}

package enum CoverageExclusionManifest {
    // Preserve ECMAScript trim rather than Foundation's different BOM/U+0085 treatment.
    private static let rationaleWhitespace = CharacterSet(
        charactersIn: "\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}"
            + "\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    package static func parse(_ contents: String, path: String) throws -> [CoverageExclusion] {
        var exclusions: [CoverageExclusion] = []
        var seen = Set<String>()
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if line.isEmpty { continue }
            let location = "\(path):\(index + 1)"
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 2 else {
                throw CoverageValidationError("\(location): expected exactly two fields separated by one tab")
            }
            let source = fields[0]
            let rationale = fields[1]
            try CoverageSourcePath.validate(source, location: location)
            guard !rationale.trimmingCharacters(in: rationaleWhitespace).isEmpty else {
                throw CoverageValidationError("\(location): exclusion rationale must not be empty")
            }
            guard !CoverageSourcePath.containsControl(rationale) else {
                throw CoverageValidationError("\(location): exclusion rationale contains a control character")
            }
            guard seen.insert(source).inserted else {
                throw CoverageValidationError("\(location): duplicate exclusion path: \(source)")
            }
            exclusions.append(CoverageExclusion(path: source, rationale: rationale))
        }
        return exclusions.sorted { $0.path < $1.path }
    }
}
