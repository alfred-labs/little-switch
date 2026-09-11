import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Repository policy filesystem")
struct RepositoryPolicyFileSystemTests {
    @Test("Recursive scanning skips build trees, follows tracked symlinks and repairs binary UTF-8")
    func scan() throws {
        try withTemporaryDirectory { root in
            for directory in [
                "Sources/Nested", "tools/.build", ".build", ".claude", ".git", ".superpowers", ".swiftpm", "build",
                "dist", "node_modules",
            ] {
                let url = root.appendingPathComponent(directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data([0xFF]).write(to: url.appendingPathComponent("file"))
            }
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked"),
                withDestinationURL: root.appendingPathComponent("Sources"))
            let snapshot = try RepositoryPolicyFileSystem.read(root: root)
            #expect(
                snapshot.files == [
                    "Sources/Nested/file": "\u{FFFD}",
                    "linked/Nested/file": "\u{FFFD}",
                ]
            )
            #expect(
                snapshot.paths == [
                    "Sources", "Sources/Nested", "Sources/Nested/file", "tools", "linked", "linked/Nested",
                    "linked/Nested/file",
                ]
            )
        }
    }

    @Test("Scanning follows a symlink that leaves the repository")
    func followsEscapingSymlinks() throws {
        try withTemporaryDirectory { outer in
            let root = outer.appendingPathComponent("repo", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: root.appendingPathComponent("file"))
            let outside = outer.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data("outside".utf8).write(to: outside.appendingPathComponent("file"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("escape"),
                withDestinationURL: outside
            )

            let snapshot = try RepositoryPolicyFileSystem.read(root: root)
            #expect(snapshot.files == ["escape/file": "outside", "file": "inside"])
            #expect(snapshot.paths == ["escape", "escape/file", "file"])
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
}
