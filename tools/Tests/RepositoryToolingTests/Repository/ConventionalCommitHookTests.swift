import Foundation
import Testing

@Suite("Git commit hook")
struct ConventionalCommitHookTests {
    @Test("Git invokes the Swift validator through mise from nested repositories without Node")
    func commitHook() throws {
        try withTemporaryDirectory { directory in
            let fixture = try CommitHookFixture(root: directory)
            let nested = fixture.root.appendingPathComponent("nested directory")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

            let accepted = try fixture.git(
                ["commit", "--quiet", "--allow-empty", "-m", "feat(hook): validate commits"], at: nested)
            #expect(accepted.status == 0, "\(accepted.stderr)")
            let rejected = try fixture.git(
                ["commit", "--quiet", "--allow-empty", "-m", "feature: invalid type"], at: nested)
            #expect(rejected.status != 0)
            #expect(rejected.stderr.contains("Conventional Commit"))
            #expect(try fixture.git(["rev-list", "--count", "HEAD"]).stdout == "1\n")

            let message = fixture.root.appendingPathComponent("message with spaces")
            try Data("Merge branch 'fixture'\n".utf8).write(to: message)
            let direct = try RepositoryProcess.run(
                fixture.hook, arguments: [message.path], directory: nested, environment: fixture.environment)
            #expect(direct == .init(status: 0, stdout: "", stderr: ""))
            let calls = try String(contentsOf: fixture.root.appendingPathComponent("calls"), encoding: .utf8)
            let prefix = "-C\n\(fixture.root.path)\nrun\n--quiet\ntools:run\n--\nrepo\ncommit-message\n"
            #expect(
                calls == prefix + ".git/COMMIT_EDITMSG\n" + prefix + ".git/COMMIT_EDITMSG\n" + prefix + message.path
                    + "\n")
        }
    }

    @Test("Repository gate and build entry points remain exposed through mise")
    func qualityGate() throws {
        let root = try RepositoryFixture.root()
        let mise = try String(contentsOf: root.appendingPathComponent(".mise.toml"), encoding: .utf8)
        for contract in [
            "[tasks.check]", "[tasks.build]", "[tasks.\"swift:coverage\"]",
            "description = \"Require exact 100 percent measured Swift line coverage\"",
        ] {
            #expect(mise.contains(contract))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Makefile").path))
    }
}

private struct CommitHookFixture {
    let root: URL
    let hook: URL
    var environment: [String: String]

    init(root directory: URL) throws {
        let physical = try RepositoryProcess.run(
            URL(fileURLWithPath: "/bin/pwd"), arguments: ["-P"], directory: directory)
        try #require(physical.status == 0)
        let root = URL(fileURLWithPath: physical.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        self.root = root
        hook = root.appendingPathComponent(".githooks/commit-msg")
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = try RepositoryFixture.root().appendingPathComponent(".githooks/commit-msg")
        #expect(FileManager.default.isExecutableFile(atPath: source.path))
        try FileManager.default.copyItem(at: source, to: hook)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment.merge([
            "PATH": bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Hook Fixture", "GIT_AUTHOR_EMAIL": "hook@example.invalid",
            "GIT_COMMITTER_NAME": "Hook Fixture", "GIT_COMMITTER_EMAIL": "hook@example.invalid",
            "HOOK_FIXTURE_ROOT": root.path, "HOOK_FIXTURE_CLI": try RepositoryProcess.toolingExecutable().path,
        ]) { _, new in new }
        for (name, body) in [
            ("mise", Self.mise),
            ("node", "echo 'Node must not run' >&2\nexit 90"),
            ("npm", "echo 'npm must not run' >&2\nexit 90"),
        ] {
            let file = bin.appendingPathComponent(name)
            try Data(("#!/bin/sh\nset -eu\n" + body + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try #require(git(["init", "--quiet"]).status == 0)
        try #require(git(["config", "core.hooksPath", ".githooks"]).status == 0)
    }

    func git(_ arguments: [String], at directory: URL? = nil) throws -> RepositoryProcess.Result {
        try RepositoryProcess.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-c", "commit.gpgsign=false"] + arguments,
            directory: directory ?? root,
            environment: environment)
    }

    private static let mise = #"""
        printf '%s\n' "$@" >> "$HOOK_FIXTURE_ROOT/calls"
        [ "$1" = -C ] && [ "$2" = "$HOOK_FIXTURE_ROOT" ]
        [ "$3" = run ] && [ "$4" = --quiet ] && [ "$5" = tools:run ] && [ "$6" = -- ]
        shift 6
        exec "$HOOK_FIXTURE_CLI" --root "$HOOK_FIXTURE_ROOT" "$@"
        """#
}
