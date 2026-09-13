import Foundation

package struct MagicStringBaseline: Codable, Equatable, Sendable {
    package struct Occurrence: Codable, Hashable, Sendable {
        package let file: String
        package let anchor: String
        package let rule: MagicKeyScanner.RuleID
        package let literal: MagicKeyScanner.Literal
        package let ordinal: Int

        init(_ violation: MagicKeyScanner.Violation) {
            file = violation.file
            anchor = violation.anchor
            rule = violation.rule
            literal = violation.literal
            ordinal = violation.ordinal
        }

        static func ordered(_ left: Self, _ right: Self) -> Bool {
            (left.file, left.anchor, left.rule.rawValue, left.literal.kind.rawValue, left.literal.value, left.ordinal)
                < (
                    right.file, right.anchor, right.rule.rawValue, right.literal.kind.rawValue, right.literal.value,
                    right.ordinal
                )
        }
    }

    package let formatVersion: Int
    package let occurrences: [Occurrence]

    package init(violations: [MagicKeyScanner.Violation]) {
        self.init(occurrences: violations.map(Occurrence.init))
    }

    init(occurrences: [Occurrence]) {
        formatVersion = 1
        self.occurrences = occurrences.sorted(by: Occurrence.ordered)
    }

    package init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        guard formatVersion == 1 else { throw invalid("unsupported format version \(formatVersion)") }
        guard Set(occurrences).count == occurrences.count else { throw invalid("duplicate occurrence") }
        for occurrence in occurrences {
            let components = occurrence.file.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                occurrence.file.hasSuffix(".swift"), !occurrence.anchor.isEmpty, occurrence.ordinal > 0
            else { throw invalid("invalid occurrence identity") }
        }
    }

    package func additionalViolations(in violations: [MagicKeyScanner.Violation]) -> [MagicKeyScanner.Violation] {
        let allowed = Set(occurrences)
        return violations.filter { !allowed.contains(Occurrence($0)) }
    }

    package func pruned(to violations: [MagicKeyScanner.Violation]) throws -> Self {
        let additions = additionalViolations(in: violations)
        guard additions.isEmpty else { throw RepositoryPolicyError(issues: additions.map(\.description)) }
        return Self(violations: violations)
    }

    package func assertDecreased(from previous: Self) throws {
        let additions = Set(occurrences).subtracting(previous.occurrences)
        guard additions.isEmpty else {
            throw invalid("may only decrease; \(additions.count) occurrence allowance(s) added")
        }
    }

    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    private func invalid(_ reason: String) -> RepositoryPolicyError {
        RepositoryPolicyError(issues: ["Invalid magic string baseline: \(reason)"])
    }
}
