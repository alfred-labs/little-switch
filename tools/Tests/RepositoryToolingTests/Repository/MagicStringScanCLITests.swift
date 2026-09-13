import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic string scan command")
struct MagicStringScanCLITests {
    @Test("The CLI initializes once, rejects additions, and prunes removed uses")
    func baselineWorkflow() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Sources/LittleSwitchCore/Protocols/Adapter.swift")
            let catalogue = root.appendingPathComponent(MagicStringPolicy.cataloguePath)
            for directory in [
                source.deletingLastPathComponent(), catalogue.deletingLastPathComponent(),
                root.appendingPathComponent("tools"),
            ] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data(#"{"formatVersion":1,"properties":[],"enums":[]}"#.utf8).write(to: catalogue)
            try Data(#"func parse() { consume(payload["type"]) }"#.utf8).write(to: source)

            let created = try run("--initialize-baseline", root: root)
            #expect(
                created == .init(status: 0, stdout: "Created magic string baseline with 1 occurrence(s).\n", stderr: "")
            )
            let baselineURL = root.appendingPathComponent(MagicStringPolicy.baselinePath)
            let original = try Data(contentsOf: baselineURL)

            let repeated = try run("--initialize-baseline", root: root)
            #expect(repeated.status != 0)
            #expect(try Data(contentsOf: baselineURL) == original)

            try Data(#"func parse() { consume(payload["type"], payload["type"]) }"#.utf8).write(to: source)
            let increased = try run("--update-baseline", root: root)
            #expect(increased.status != 0)
            #expect(increased.stderr.contains(#"raw key "type""#))
            #expect(try Data(contentsOf: baselineURL) == original)

            try Data("func parse() {}".utf8).write(to: source)
            let reduced = try run("--update-baseline", root: root)
            #expect(
                reduced == .init(status: 0, stdout: "Updated magic string baseline to 0 occurrence(s).\n", stderr: ""))
            #expect(try MagicStringBaseline(data: Data(contentsOf: baselineURL)).occurrences.isEmpty)
        }
    }

    @Test("Directory diagnostics retain their positioned key labels")
    func printsDiagnostics() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("Example")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("let value = payload[\"key\"]\nlet map = [\"type\": 1]".utf8)
                .write(to: directory.appendingPathComponent("Adapter.swift"))

            let result = try ToolingCLI.run(
                ["repo", "magic-strings", "Example", "--root", root.path], currentDirectory: root)
            #expect(
                result
                    == .init(
                        status: 0,
                        stdout:
                            "Adapter.swift:1:21: raw key \"key\" (subscript)\nAdapter.swift:2:12: raw key \"type\" (dict-literal)\n\n2 violation(s) found.\n",
                        stderr: ""))
        }
    }

    private func run(_ option: String, root: URL) throws -> ToolingCLI.Result {
        try ToolingCLI.run(["repo", "magic-strings", option, "--root", root.path], currentDirectory: root)
    }
}
