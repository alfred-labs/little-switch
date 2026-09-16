import Foundation
import Testing

@testable import RepositoryTooling

@Suite("User-visible string source traversal")
struct UserVisibleStringFileSystemTests {
    @Test("A regular file cannot be mistaken for an empty source directory")
    func rejectsFileRoot() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Copy.swift")
            try Data(#"Text("Unscanned")"#.utf8).write(to: source)
            #expect(throws: RepositoryPolicyError(issues: ["UI string scan requires a directory: \(source.path)"])) {
                try UserVisibleStringScanner.scan(directory: source)
            }
        }
    }

    @Test("A linked scan root resolves while links inside it cannot escape or create cycles")
    func symbolicLinks() throws {
        try withTemporaryDirectory { root in
            let sources = root.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Data(#"Text("Visible")"#.utf8).write(to: sources.appendingPathComponent("Copy.swift"))
            let external = root.appendingPathComponent("External.swift")
            try Data(#"Text("Outside the scope")"#.utf8).write(to: external)
            let alias = root.appendingPathComponent("Alias")
            for (link, destination) in [
                (alias, sources), (sources.appendingPathComponent("Cycle"), sources),
                (sources.appendingPathComponent("Linked.swift"), external),
                (sources.appendingPathComponent("Broken.swift"), root.appendingPathComponent("Missing")),
            ] {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
            }

            #expect(
                try UserVisibleStringScanner.scan(directory: alias) == [
                    .init(
                        file: "Copy.swift",
                        line: 1,
                        column: 6,
                        api: "Text",
                        text: "Visible",
                        staticSegments: ["Visible"])
                ])
        }
    }

    @Test("Unreadable nested directories fail the scan instead of returning a partial inventory")
    func unreadableDirectory() throws {
        try withTemporaryDirectory { root in
            let locked = root.appendingPathComponent("Locked")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try Data(#"Text("Unscanned")"#.utf8).write(to: locked.appendingPathComponent("Copy.swift"))
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }

            #expect(throws: (any Error).self) { try UserVisibleStringScanner.scan(directory: root) }
        }
    }
}
