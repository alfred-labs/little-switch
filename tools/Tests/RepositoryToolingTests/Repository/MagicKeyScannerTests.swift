import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic key scanner")
struct MagicKeyScannerTests {
    @Test("Subscripts and dictionary literals report positioned raw keys")
    func reportsViolationsWithPositions() {
        let source = """
        let value = headers["x-api-key"]
        let map = ["type": 1, other: 2]
        """

        let violations = MagicKeyScanner.scan(source: source, filePath: "Protocols/Example.swift")

        #expect(violations.map(\.kind) == ["subscript", "dict-literal"])
        #expect(violations.map(\.key) == ["x-api-key", "type"])
        #expect(
            violations.map(\.description) == [
                "Protocols/Example.swift:1:21: raw key \"x-api-key\" (subscript)",
                "Protocols/Example.swift:2:12: raw key \"type\" (dict-literal)",
            ])
    }

    @Test("Interpolated keys stay visible instead of crashing the scan")
    func recordsInterpolatedKeys() {
        let violations = MagicKeyScanner.scan(
            source: #"let value = headers["\(name)-key"]"#, filePath: "Example.swift")
        #expect(violations.map(\.key) == ["<interpolated>"])
    }

    @Test("Directory scan filters the allowlist and sorts deterministically")
    func directoryScanFiltersAndSorts() throws {
        // The enumerator resolves the symlinked temporary root (/var →
        // /private/var), so the scan root must resolve before children are
        // appended or the relative prefix never strips.
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = temporary.appendingPathComponent("magic-key-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("A.swift")
        let second = root.appendingPathComponent("sub/B.swift")
        try FileManager.default.createDirectory(
            at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"let allowed = payload["kind"]"#.utf8).write(to: first)
        try Data(
            #"let blocked = payload["status"]"#.utf8
        ).write(to: second)

        let violations = try MagicKeyScanner.scan(directory: root, allowlist: ["kind"])

        #expect(violations.map(\.description) == ["sub/B.swift:1:23: raw key \"status\" (subscript)"])
        #expect(try MagicKeyScanner.scan(directory: root.appendingPathComponent("missing")).isEmpty)
    }
}
