import Foundation

package enum ConventionalCommit {
    static let allowedTypes = [
        "feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert",
    ]

    private static let generatedPrefixes = ["Merge ", "Revert \"", "fixup! ", "squash! "]

    // Preserve JavaScript String.trim(): Foundation also trims U+0085 and does not trim the BOM.
    private static let subjectWhitespace = CharacterSet(
        charactersIn: "\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}"
            + "\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    package static func validate(_ message: String) -> Result<String, ConventionalCommitError> {
        let subject =
            message.components(separatedBy: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: subjectWhitespace) }
            .first { !$0.isEmpty && !$0.utf8.starts(with: "#".utf8) } ?? ""

        if generatedPrefixes.contains(where: { subject.utf8.starts(with: $0.utf8) }) {
            return .success(subject)
        }

        let pattern = /^([a-z]+)(?:\([^()\r\n]+\))?!?: [^\r\n\u{2028}\u{2029}]+$/
            .matchingSemantics(.unicodeScalar)
        if let match = subject.wholeMatch(of: pattern), allowedTypes.contains(String(match.1)) {
            return .success(subject)
        }

        return .failure(.invalidSubject(subject))
    }
}
