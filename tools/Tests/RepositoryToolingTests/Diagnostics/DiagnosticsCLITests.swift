import Foundation
import Testing

@Suite("Session diagnostic command")
struct DiagnosticsCLITests {
    @Test("The command orders segments by modification date and handles long or unterminated lines")
    func chronologicalFiles() throws {
        try withTemporaryDirectory { root in
            let logs = root.appendingPathComponent("Logs with spaces")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let older = logs.appendingPathComponent("traffic-z.jsonl")
            let newer = logs.appendingPathComponent("traffic-a.jsonl")
            var first = Data("{bad line\n".utf8)
            first.append(try request(definitions: 2))
            first.append(10)
            try first.write(to: older)
            try request(definitions: 1).write(to: newer)
            try request(definitions: 99).write(to: logs.appendingPathComponent("unrelated.jsonl"))
            try FileManager.default.createDirectory(
                at: logs.appendingPathComponent("traffic-directory.jsonl"), withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: older.path)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 20)], ofItemAtPath: newer.path)
            let result = try ToolingCLI.run(
                ["diagnostics", "session-tool-defs", "--root", root.path, "Logs with spaces", "--mounted", "20"],
                currentDirectory: logs)
            #expect(result.status == 0)
            #expect(result.stderr.isEmpty)
            #expect(
                result.stdout
                    == "model                     reqs   TS last_defs max_defs  ratio\nfixture                      2  non         1        2  1/20\n"
            )
        }
    }

    @Test("Empty logs produce an explicit empty report")
    func emptyDirectory() throws {
        try withTemporaryDirectory { root in
            let result = try ToolingCLI.run(
                ["--root", root.path, "diagnostics", "session-tool-defs", "."], currentDirectory: root)
            #expect(result.status == 0)
            #expect(result.stdout == "no sessions found\n")
        }
    }

    @Test("Missing paths and invalid arguments fail without a partial report", arguments: [false, true])
    func failures(invalidArgument: Bool) throws {
        try withTemporaryDirectory { root in
            var arguments = ["diagnostics", "session-tool-defs", "missing"]
            if invalidArgument { arguments += ["--mounted", "invalid"] }
            let result = try ToolingCLI.run(arguments, currentDirectory: root)
            #expect(result.status != 0)
            #expect(result.stdout.isEmpty)
            #expect(!result.stderr.isEmpty)
        }
    }

    private func request(definitions: Int) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "fixture",
            "messages": [["role": "user", "content": String(repeating: "synthetic", count: 10_000)]],
            "tools": (0..<definitions).map { ["name": "mcp__tool_\($0)"] },
        ])
        return try JSONSerialization.data(withJSONObject: [
            "action": ["claudeRequestBody": ["_0": body.base64EncodedString()]]
        ])
    }
}
