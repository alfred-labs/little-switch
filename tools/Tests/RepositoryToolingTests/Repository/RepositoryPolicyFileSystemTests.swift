import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Repository policy filesystem")
struct RepositoryPolicyFileSystemTests {
    @Test("Recursive scanning skips build trees and symlinks but repairs binary UTF-8 as the old policy did")
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
            #expect(snapshot.files == ["Sources/Nested/file": "\u{FFFD}"])
            #expect(snapshot.paths == ["Sources", "Sources/Nested", "Sources/Nested/file", "tools", "linked"])
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
