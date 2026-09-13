import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic string baseline")
struct MagicStringBaselineTests {
    @Test("An additional identical literal exceeds its anchored occurrence allowance")
    func rejectsIdenticalAddition() {
        let baseline = MagicStringBaseline(violations: scan(#"func parse() { consume(payload["type"]) }"#))
        let current = scan(#"func parse() { consume(payload["type"], payload["type"]) }"#)

        #expect(baseline.additionalViolations(in: current) == [current[1]])
    }

    @Test("Line movement preserves identity and removal can only shrink the baseline")
    func movesAndRemovals() throws {
        let baseline = MagicStringBaseline(violations: scan(#"func parse() { consume(payload["type"]) }"#))
        let moved = scan("\n// Documentation\nfunc parse() {\n    consume(payload[\"type\"])\n}")

        #expect(baseline.additionalViolations(in: moved).isEmpty)
        #expect(try baseline.pruned(to: moved) == baseline)
        #expect(try baseline.pruned(to: []).occurrences.isEmpty)
        #expect(try MagicStringBaseline(data: baseline.encoded()) == baseline)
    }

    @Test("An allowance cannot move to another declaration, file, rule or literal")
    func rejectsIdentityChanges() {
        let baseline = MagicStringBaseline(violations: scan(#"func parse() { consume(payload["type"]) }"#))
        let changes = [
            scan(#"func other() { consume(payload["type"]) }"#)[0],
            MagicKeyScanner.scan(source: #"func parse() { consume(payload["type"]) }"#, filePath: "Other.swift")[0],
            scan(#"func parse() { consume(["type": 1]) }"#)[0],
            scan(#"func parse() { consume(payload["role"]) }"#)[0],
        ]

        #expect(baseline.additionalViolations(in: changes) == changes)
    }

    @Test("Refreshing and editing a baseline cannot add allowances")
    func rejectsGrowth() throws {
        let original = scan(#"func parse() { consume(payload["type"]) }"#)
        let added = scan(#"func parse() { consume(payload["type"], payload["type"]) }"#)
        let baseline = MagicStringBaseline(violations: original)

        #expect(throws: RepositoryPolicyError.self) { try baseline.pruned(to: added) }
        #expect(throws: RepositoryPolicyError.self) {
            try MagicStringBaseline(violations: added).assertDecreased(from: baseline)
        }
        try MagicStringBaseline(violations: []).assertDecreased(from: baseline)
    }

    @Test("Malformed baseline identities fail closed", arguments: ["duplicate", "ordinal", "path", "version"])
    func rejectsMalformedBaseline(problem: String) throws {
        let occurrence =
            #"{"file":"Example.swift","anchor":"func parse()","rule":"subscriptKey","literal":{"kind":"string","value":"type"},"ordinal":1}"#
        let rows = problem == "duplicate" ? occurrence + "," + occurrence : occurrence
        var source = "{\"formatVersion\":1,\"occurrences\":[\(rows)]}"
        if problem == "ordinal" { source = source.replacingOccurrences(of: #""ordinal":1"#, with: #""ordinal":0"#) }
        if problem == "path" { source = source.replacingOccurrences(of: "Example.swift", with: "../Example.swift") }
        if problem == "version" {
            source = source.replacingOccurrences(of: #""formatVersion":1"#, with: #""formatVersion":2"#)
        }

        #expect(throws: (any Error).self) { try MagicStringBaseline(data: Data(source.utf8)) }
    }

    private func scan(_ source: String) -> [MagicKeyScanner.Violation] {
        MagicKeyScanner.scan(source: source, filePath: "Example.swift")
    }
}
