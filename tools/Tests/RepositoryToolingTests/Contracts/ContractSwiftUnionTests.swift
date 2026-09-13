import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Generated exhaustive union complexity", .serialized)
struct ContractSwiftUnionTests {
    private let directive = "// swiftlint:disable:next cyclomatic_complexity"

    @Test func largeTaggedUnionKeepsExhaustiveDispatchAndPassesTheRepositoryComplexityRule() throws {
        let source = try taggedUnion(variants: 26)
        #expect(source.components(separatedBy: directive).count - 1 == 2)
        #expect(source.contains("Pure SDK variant mapping; keep exhaustive dispatch and explicit unknown handling."))
        #expect(source.contains("switch discriminator"))
        #expect(source.contains("switch self"))
        #expect(source.contains("case unknown(type: String, payload: JSONValue)"))
        for index in 0..<26 {
            #expect(source.contains("case event\(index)(LargeUnionEvent\(index))"))
        }

        let checked = try lint(source)
        #expect(checked.status == 0, "\(checked.stdout)\(checked.stderr)")

        let withoutExemption = source.replacingOccurrences(of: "    \(directive)\n", with: "")
        let rejected = try lint(withoutExemption)
        #expect(rejected.status != 0)
        let diagnostics = rejected.stdout + rejected.stderr
        #expect(diagnostics.components(separatedBy: "Cyclomatic Complexity Violation").count - 1 == 2)
    }

    @Test(arguments: [(18, 0), (19, 1), (20, 2), (21, 2)])
    func exemptionTracksOnlyMethodsOverTheBranchLimit(variants: Int, expectedExemptions: Int) throws {
        let source = try taggedUnion(variants: variants)
        #expect(source.components(separatedBy: directive).count - 1 == expectedExemptions)
        let checked = try lint(source)
        #expect(checked.status == 0, "\(checked.stdout)\(checked.stderr)")
    }

    private func taggedUnion(variants: Int) throws -> String {
        let branches = (0..<variants)
            .map { index in
                """
                {"type":"object","properties":{"type":{"const":"event_\(index)"}},"required":["type"]}
                """
            }
            .joined(separator: ",")
        let data = Data("{\"anyOf\":[\(branches)]}".utf8)
        let graph = try ContractSchemaReader.read(data: data, rootID: "LargeUnion")
        return try #require(
            ContractSwiftEmitter.emit(graph: graph).first { $0.relativePath.hasSuffix("/LargeUnion.swift") }
        ).source
    }

    private func lint(_ source: String) throws -> RepositoryProcess.Result {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("LargeUnion.swift")
            try Data(source.utf8).write(to: file)
            let configuration = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".swiftlint.yml")
            return try RepositoryProcess.run(
                URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swiftlint", "lint", "--strict", "--quiet", "--no-cache", "--only-rule", "cyclomatic_complexity",
                    "--config", configuration.path, file.path,
                ],
                directory: root
            )
        }
    }
}
