import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Magic string baseline Git history")
struct MagicStringBaselineStoreTests {
    @Test("Baseline growth fails in dirty and clean checkouts", arguments: ["dirty", "committed", "later-pruned"])
    func rejectsGrowth(state: String) throws {
        try withTemporaryDirectory { root in
            let fixture = try MagicStringGitFixture(root: root)
            try fixture.save(keys: ["type"])
            try fixture.commit()
            try fixture.save(keys: ["type", "role", "content"])
            if state != "dirty" { try fixture.commit() }
            if state == "later-pruned" {
                try fixture.save(keys: ["type", "role"])
                try fixture.commit()
            }

            #expect(try fixture.issues().contains { $0.contains("may only decrease") })
        }
    }

    @Test("A retired occurrence cannot return in a later commit")
    func rejectsReintroduction() throws {
        try withTemporaryDirectory { root in
            let fixture = try MagicStringGitFixture(root: root)
            for keys in [["type", "role"], ["type"], ["type", "role"]] {
                try fixture.save(keys: keys)
                try fixture.commit()
            }

            #expect(try fixture.issues().contains { $0.contains("may only decrease") })
        }
    }

    @Test("The first baseline can be initialized and committed without an older baseline")
    func permitsFirstIntroduction() throws {
        try withTemporaryDirectory { root in
            let fixture = try MagicStringGitFixture(root: root)
            try fixture.save(keys: ["type"], includeBaseline: false)

            #expect(try MagicStringPolicy.updateBaseline(root: root, action: .initialize) == 1)
            try fixture.commit()
            #expect(try fixture.issues().isEmpty)
            try fixture.save(keys: [])
            try fixture.commit()
            #expect(try fixture.issues().isEmpty)
        }
    }

    @Test("Deleting a committed baseline cannot reset its allowance", arguments: [false, true])
    func rejectsDeletionReset(reintroduced: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try MagicStringGitFixture(root: root)
            try fixture.save(keys: ["type"])
            try fixture.commit()
            try FileManager.default.removeItem(at: root.appendingPathComponent(MagicStringPolicy.baselinePath))
            try fixture.commit()
            if reintroduced {
                try fixture.save(keys: ["type"])
                try fixture.commit()
                #expect(try fixture.issues().contains { $0.contains("may only decrease") })
            } else {
                #expect(throws: RepositoryPolicyError.self) {
                    try MagicStringPolicy.updateBaseline(root: root, action: .initialize)
                }
            }
        }
    }

    @Test("Malformed historical baselines fail closed")
    func rejectsMalformedHistory() throws {
        try withTemporaryDirectory { root in
            let fixture = try MagicStringGitFixture(root: root)
            try fixture.save(keys: ["type"])
            try fixture.commit()
            try Data("{".utf8).write(to: root.appendingPathComponent(MagicStringPolicy.baselinePath))
            try fixture.commit()
            try fixture.save(keys: ["type"])
            try fixture.commit()

            #expect(throws: (any Error).self) { try MagicStringBaselineStore.committed(root: root) }
        }
    }

    @Test("Shallow history fails closed instead of treating its boundary as initialization")
    func rejectsShallowHistory() throws {
        try withTemporaryDirectory { directory in
            let origin = directory.appendingPathComponent("origin")
            let fixture = try MagicStringGitFixture(root: origin)
            try fixture.save(keys: ["type"])
            try fixture.commit()
            let clone = directory.appendingPathComponent("shallow")
            try fixture.git(["clone", "--quiet", "--depth=1", origin.absoluteString, clone.path])

            #expect(throws: RepositoryPolicyError.self) { try MagicStringBaselineStore.committed(root: clone) }
        }
    }

    @Test("Unreadable Git metadata does not disable the baseline gate")
    func rejectsGitReadFailure() throws {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)

            #expect(throws: RepositoryPolicyError.self) { try MagicStringBaselineStore.committed(root: root) }
        }
    }
}

private struct MagicStringGitFixture {
    let root: URL
    private let sourcePath = "Sources/LittleSwitchCore/Protocols/Adapter.swift"

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "--quiet"])
        try git(["commit", "--quiet", "--allow-empty", "-m", "test: create repository"])
    }

    func save(keys: [String], includeBaseline: Bool = true) throws {
        let expressions = keys.map { "payload[\"\($0)\"]" }.joined(separator: ", ")
        let source = "func parse() { consume(\(expressions)) }"
        try write(Data(source.utf8), to: sourcePath)
        try write(Data(#"{"formatVersion":1,"properties":[],"enums":[]}"#.utf8), to: MagicStringPolicy.cataloguePath)
        if includeBaseline {
            let baseline = MagicStringBaseline(violations: MagicKeyScanner.scan(source: source, filePath: sourcePath))
            try write(baseline.encoded(), to: MagicStringPolicy.baselinePath)
        }
    }

    func commit() throws {
        try git(["add", "--", sourcePath, MagicStringPolicy.cataloguePath, MagicStringPolicy.baselinePath])
        try git(["commit", "--quiet", "-m", "test: update baseline fixture"])
    }

    func issues() throws -> [String] {
        let files = try RepositoryPolicyFileSystem.read(root: root).files
        return try MagicStringPolicy.check(
            files: files, committedBaseline: MagicStringBaselineStore.committed(root: root))
    }

    func git(_ arguments: [String]) throws {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment.merge([
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Baseline Fixture", "GIT_AUTHOR_EMAIL": "baseline@example.invalid",
            "GIT_COMMITTER_NAME": "Baseline Fixture", "GIT_COMMITTER_EMAIL": "baseline@example.invalid",
        ]) { _, new in new }
        let result = try RepositoryProcess.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + arguments,
            directory: root,
            environment: environment)
        try #require(result.status == 0, "\(result.stderr)")
    }

    private func write(_ data: Data, to path: String) throws {
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination)
    }
}
