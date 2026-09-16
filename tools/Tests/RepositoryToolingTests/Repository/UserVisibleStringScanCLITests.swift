import Foundation
import Testing

@Suite("User-visible string scan command")
struct UserVisibleStringScanCLITests {
    @Test("The default scan fails on untranslated copy with positioned findings and preserves the source")
    func defaultDirectory() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("Sources/LittleSwitchUI")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("Copy.swift")
            let contents = Data("Text(L10n.resource(\"Localized\"))\nText(\"Raw\")\n".utf8)
            try contents.write(to: source)

            let result = try ToolingCLI.run(["repo", "ui-strings", "--root", root.path], currentDirectory: root)
            #expect(
                result
                    == .init(
                        status: 1,
                        stdout: "Copy.swift:2:6: Text: \"Raw\" segments: Raw\n\n1 finding(s).\n",
                        stderr: ""))
            #expect(try Data(contentsOf: source) == contents)
        }
    }

    @Test("Localized copy, verbatim text and the shared product identity pass the command")
    func explicitDirectory() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("Localized sources")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let contents = #"""
                Text(L10n.resource("Localized"))
                Text(verbatim: "X-Api-Key")
                SwiftUI.Text(verbatim: "127.0.0.1:11436")
                window.title = ProductIdentity.displayName
                """#
            try Data(contents.utf8).write(to: directory.appendingPathComponent("Copy.swift"))

            let result = try ToolingCLI.run(
                ["--root", root.path, "repo", "ui-strings", "Localized sources"], currentDirectory: directory)
            #expect(
                result
                    == .init(
                        status: 0, stdout: "No user-visible string findings in Localized sources.\n", stderr: ""))
        }
    }

    @Test("Missing paths and files fail without claiming a successful scan", arguments: [false, true])
    func invalidDirectory(isFile: Bool) throws {
        try withTemporaryDirectory { root in
            let path = root.appendingPathComponent("Invalid")
            if isFile { try Data("Text(\"Unscanned\")".utf8).write(to: path) }

            let result = try ToolingCLI.run(["repo", "ui-strings", path.path], currentDirectory: root)
            #expect(result.status != 0)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.contains("Invalid"))
        }
    }
}
