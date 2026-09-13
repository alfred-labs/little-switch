import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Repository policy filesystem")
struct RepositoryPolicyFileSystemTests {
    @Test("Removed debt must be pruned so migrated adapters cannot reuse old allowances")
    func requiresPruningResolvedAllowances() throws {
        let path = "Sources/LittleSwitchCore/Protocols/Adapter.swift"
        let original = #"func parse() { consume(payload["type"]) }"#
        let baseline = MagicStringBaseline(violations: MagicKeyScanner.scan(source: original, filePath: path))
        let baselineText = try #require(String(data: baseline.encoded(), encoding: .utf8))
        let issues = MagicStringPolicy.check(files: [
            path: "func parse() {}",
            MagicStringPolicy.cataloguePath: #"{"formatVersion":1,"properties":[],"enums":[]}"#,
            MagicStringPolicy.baselinePath: baselineText,
        ])

        #expect(
            issues == [
                "Magic string baseline has 1 resolved occurrence(s); run mise run --quiet tools:run -- repo magic-strings --update-baseline"
            ])
    }

    @Test("Editing the current baseline cannot grow the committed allowance")
    func rejectsBaselineGrowthAgainstCommittedVersion() throws {
        let path = "Sources/LittleSwitchCore/Protocols/Adapter.swift"
        let original = #"func parse() { consume(payload["type"]) }"#
        let added = #"func parse() { consume(payload["type"], payload["type"]) }"#
        let previous = MagicStringBaseline(violations: MagicKeyScanner.scan(source: original, filePath: path))
        let expanded = MagicStringBaseline(violations: MagicKeyScanner.scan(source: added, filePath: path))
        let expandedText = try #require(String(data: expanded.encoded(), encoding: .utf8))
        let issues = MagicStringPolicy.check(
            files: [
                path: added,
                MagicStringPolicy.cataloguePath: #"{"formatVersion":1,"properties":[],"enums":[]}"#,
                MagicStringPolicy.baselinePath: expandedText,
            ],
            committedBaseline: previous
        )

        #expect(issues.contains { $0.contains("may only decrease") })
    }

    @Test("The occurrence baseline replaces global key allowances")
    func rejectsAnAdditionalAllowedKey() throws {
        try withTemporaryDirectory { root in
            let path = "Sources/LittleSwitchCore/Protocols/Adapter.swift"
            let original = #"func parse() { consume(payload["type"]) }"#
            try write(original, to: path, root: root)
            try write("type\n", to: "tools/magic-key-allowlist.txt", root: root)
            try write(
                #"{"formatVersion":1,"properties":[],"enums":[]}"#, to: "schemas/upstream/catalog.json", root: root)
            let baseline = MagicStringBaseline(violations: MagicKeyScanner.scan(source: original, filePath: path))
            try baseline.encoded().write(to: root.appendingPathComponent("tools/magic-string-baseline.json"))
            try write(#"func parse() { consume(payload["type"], payload["type"]) }"#, to: path, root: root)

            let issues = try policyIssues(root: root)
            #expect(issues.filter { $0.contains(#"raw key "type""#) }.count == 1)
        }
    }

    @Test("New raw accesses in gateway and tool adapters fail the same gate", arguments: ["Gateway", "Tools"])
    func coversMigratedAdapters(directory: String) throws {
        try withTemporaryDirectory { root in
            try write(
                #"let value = payload["x-new"]"#, to: "Sources/LittleSwitchCore/\(directory)/Adapter.swift", root: root)
            try write(
                #"{"formatVersion":1,"properties":[],"enums":[]}"#, to: "schemas/upstream/catalog.json", root: root)
            try write(#"{"formatVersion":1,"occurrences":[]}"#, to: "tools/magic-string-baseline.json", root: root)

            let issues = try policyIssues(root: root)
            #expect(issues.contains { $0.contains(#"raw key "x-new""#) })
        }
    }

    @Test("Deleting the baseline does not disable the magic string gate")
    func requiresBaseline() throws {
        try withTemporaryDirectory { root in
            let issues = try policyIssues(root: root)
            #expect(issues.contains { $0.contains("Missing magic string baseline:") })
        }
    }

    @Test("Recursive scanning skips build trees, follows repository-local symlinks and repairs binary UTF-8")
    func scan() throws {
        try withTemporaryDirectory { root in
            for directory in [
                "Sources/Nested", "tools/.build", ".build", ".claude", ".git", ".superpowers", ".swiftpm", "build",
                "dist", "node_modules", ".worktrees/other-branch/Sources",
            ] {
                let url = root.appendingPathComponent(directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data([0xFF]).write(to: url.appendingPathComponent("file"))
            }
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked"),
                withDestinationURL: root.appendingPathComponent("Sources"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked-file"),
                withDestinationURL: root.appendingPathComponent("Sources/Nested/file"))
            let snapshot = try RepositoryPolicyFileSystem.read(root: root)
            #expect(
                snapshot.files == [
                    "Sources/Nested/file": "\u{FFFD}",
                    "linked/Nested/file": "\u{FFFD}",
                    "linked-file": "\u{FFFD}",
                ]
            )
            #expect(
                snapshot.paths == [
                    "Sources", "Sources/Nested", "Sources/Nested/file", "tools", "linked", "linked/Nested",
                    "linked/Nested/file", "linked-file",
                ]
            )
        }
    }

    @Test("External documentation links do not read sibling checkouts", arguments: [false, true])
    func externalDocumentation(isCheckedOut: Bool) throws {
        try withTemporaryDirectory { outer in
            let root = outer.appendingPathComponent("repo", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: root.appendingPathComponent("file"))
            let outside = outer.appendingPathComponent("repo-internals/docs", isDirectory: true)
            if isCheckedOut {
                try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
                try Data("outside".utf8).write(to: outside.appendingPathComponent("file"))
            }
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("docs").path,
                withDestinationPath: "../repo-internals/docs"
            )

            let snapshot = try RepositoryPolicyFileSystem.read(root: root)
            #expect(snapshot.files == ["file": "inside"])
            #expect(snapshot.paths == ["docs", "file"])
        }
    }

    @Test("Scanning does not recurse through an ancestor symlink")
    func skipsAncestorSymlinks() throws {
        try withTemporaryDirectory { root in
            try Data("inside".utf8).write(to: root.appendingPathComponent("file"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("self"),
                withDestinationURL: root
            )

            let snapshot = try RepositoryPolicyFileSystem.read(root: root)
            #expect(snapshot.files == ["file": "inside"])
            #expect(snapshot.paths == ["file", "self"])
        }
    }

    @Test("Missing repositories and missing policy content produce failures")
    func checkErrors() throws {
        try withTemporaryDirectory { root in
            #expect(throws: (any Error).self) {
                try RepositoryPolicyFileSystem.check(root: root.appendingPathComponent("missing"))
            }
            do {
                try RepositoryPolicyFileSystem.check(root: root)
                Issue.record("Expected missing repository contracts to fail")
            } catch {
                #expect(error.localizedDescription.contains("Missing policy file:"))
                #expect(error.localizedDescription.contains("packaging/Info.plist"))
            }
        }
    }

    private func write(_ source: String, to path: String, root: URL) throws {
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: destination)
    }

    private func policyIssues(root: URL) throws -> [String] {
        do {
            try RepositoryPolicyFileSystem.check(root: root)
            return []
        } catch let error as RepositoryPolicyError {
            return error.issues
        }
    }
}
