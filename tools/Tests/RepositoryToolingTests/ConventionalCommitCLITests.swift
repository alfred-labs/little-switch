import Foundation
import Testing

@Suite("Conventional commit command")
struct ConventionalCommitCLITests {
    @Test("An explicit root works at each command level with paths containing spaces", arguments: [0, 1, 2])
    func explicitRoot(optionIndex: Int) throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("repository with spaces", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("feat(gateway): route Claude models\n".utf8)
                .write(to: root.appendingPathComponent("commit message.txt"))
            try Data("Invalid subject in the invocation directory\n".utf8)
                .write(to: directory.appendingPathComponent("commit message.txt"))
            var arguments = ["repo", "commit-message", "commit message.txt"]
            arguments.insert(contentsOf: ["--root", root.path], at: optionIndex)

            let result = try ToolingCLI.run(arguments, currentDirectory: directory)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }

    @Test("The invocation directory is the default root")
    func defaultRoot() throws {
        try withTemporaryDirectory { directory in
            try Data("fix!: change profile format\n".utf8)
                .write(to: directory.appendingPathComponent("commit message.txt"))

            let result = try ToolingCLI.run(
                ["repo", "commit-message", "commit message.txt"], currentDirectory: directory)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }

    @Test("A relative root is resolved from the invocation directory")
    func relativeRoot() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("nested repository", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("fixup! feat: route models\n".utf8).write(to: root.appendingPathComponent("message"))
            try Data("Invalid subject in the invocation directory\n".utf8)
                .write(to: directory.appendingPathComponent("message"))

            let result = try ToolingCLI.run(
                ["--root", "nested repository", "repo", "commit-message", "message"], currentDirectory: directory)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }

    @Test("An absolute message path is independent of the repository root")
    func absoluteMessagePath() throws {
        try withTemporaryDirectory { directory in
            let message = directory.appendingPathComponent("commit message.txt")
            try Data("chore: maintain tooling\n".utf8).write(to: message)
            let root = directory.appendingPathComponent("other repository", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let result = try ToolingCLI.run(
                ["--root", root.path, "repo", "commit-message", message.path], currentDirectory: root)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }

    @Test("Invalid subjects produce the complete diagnostic on stderr", arguments: ["feature: route models", ""])
    func invalidMessage(subject: String) throws {
        try withTemporaryDirectory { directory in
            try Data("\(subject)\n".utf8).write(to: directory.appendingPathComponent("message"))

            let result = try ToolingCLI.run(["repo", "commit-message", "message"], currentDirectory: directory)

            let expected = """
                Error: Commit message must follow the Conventional Commit format: type(scope)!?: subject
                Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
                Examples: feat(gateway): route Claude models, fix: restore Claude profile, chore(release): LittleSwitch v0.1.0
                Received: \(subject.isEmpty ? "<empty>" : subject)

                """
            #expect(result == .init(status: 1, stdout: "", stderr: expected))
        }
    }

    @Test("A missing argument reports usage on stderr")
    func missingArgument() throws {
        try withTemporaryDirectory { directory in
            let result = try ToolingCLI.run(["repo", "commit-message"], currentDirectory: directory)

            #expect(result.status != 0)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.contains("Missing expected argument '<path>'"))
            #expect(result.stderr.contains("Usage: littleswitch-tools repo commit-message"))
        }
    }

    @Test("An unreadable file reports its resolved path on stderr")
    func unreadableFile() throws {
        try withTemporaryDirectory { directory in
            let result = try ToolingCLI.run(["repo", "commit-message", "missing message"], currentDirectory: directory)

            #expect(result.status == 1)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.contains("Cannot read commit message file"))
            #expect(result.stderr.contains(directory.appendingPathComponent("missing message").path))
        }
    }

    @Test("Help documents the path and root option")
    func help() throws {
        try withTemporaryDirectory { directory in
            let result = try ToolingCLI.run(["repo", "commit-message", "--help"], currentDirectory: directory)

            #expect(result.status == 0)
            #expect(result.stderr.isEmpty)
            #expect(result.stdout.contains("USAGE: littleswitch-tools repo commit-message"))
            #expect(result.stdout.contains("<path>"))
            #expect(result.stdout.contains("--root <root>"))
        }
    }

    @Test("Invalid UTF-8 bytes are repaired as in the existing Node validator")
    func repairedUTF8() throws {
        try withTemporaryDirectory { directory in
            var message = Data("feat: repair ".utf8)
            message.append(0xFF)
            try message.write(to: directory.appendingPathComponent("message"))

            let result = try ToolingCLI.run(["repo", "commit-message", "message"], currentDirectory: directory)

            #expect(result == .init(status: 0, stdout: "", stderr: ""))
        }
    }
}
