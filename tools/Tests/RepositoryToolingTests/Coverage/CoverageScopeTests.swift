import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Coverage source scope")
struct CoverageScopeTests {
    @Test("Recursive discovery partitions every target deterministically")
    func recursive() throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(
                at: root,
                sources: ["Sources/Zeta/Z.swift", "Sources/Alpha/Nested/A.swift", "Sources/Alpha/Ignore.txt"],
                exclusions: "Sources/Zeta/Z.swift\tnative process boundary\n")

            let scope = try CoverageScope.load(root: root)

            #expect(scope.all == ["Sources/Alpha/Nested/A.swift", "Sources/Zeta/Z.swift"])
            #expect(scope.measured == ["Sources/Alpha/Nested/A.swift"])
            #expect(scope.excluded == [.init(path: "Sources/Zeta/Z.swift", rationale: "native process boundary")])
        }
    }

    @Test("Explicit package root and package-relative manifest classify tooling independently")
    func toolingPackage() throws {
        try withTemporaryDirectory { repository in
            let root = repository.appendingPathComponent("tools", isDirectory: true)
            try CoverageFixture.write(
                at: root,
                sources: ["Sources/CLI/Main.swift", "Sources/Domain/Rule.swift"],
                exclusions: "Sources/CLI/Main.swift\targument parser boundary\n",
                manifest: "ci/tooling.tsv")
            let scope = try CoverageScope.load(root: root, manifestPath: "ci/tooling.tsv")
            #expect(scope.measured == ["Sources/Domain/Rule.swift"])
            #expect(scope.all.count == 2)
        }
    }

    @Test("A root symlink is canonicalized without permitting symlinks inside Sources")
    func canonicalRoot() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("actual repository", isDirectory: true)
            try CoverageFixture.write(at: root)
            let link = directory.appendingPathComponent("linked repository")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
            let nested = link.appendingPathComponent("unused/..", isDirectory: true)
            #expect(try CoverageScope.load(root: nested) == CoverageScope.load(root: root))
        }
    }

    @Test("Missing and non-directory Sources fail", arguments: [false, true])
    func invalidSources(file: Bool) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            let sources = root.appendingPathComponent("Sources")
            try FileManager.default.removeItem(at: sources)
            if file { try Data("not a directory".utf8).write(to: sources) }
            expectCoverageFailure(
                file ? "production source path is not a directory" : "production source directory is missing"
            ) {
                _ = try CoverageScope.load(root: root)
            }
        }
    }

    @Test("Missing and non-file manifests fail", arguments: [false, true])
    func invalidManifest(directory: Bool) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            let manifest = root.appendingPathComponent(CoverageFixture.manifest)
            try FileManager.default.removeItem(at: manifest)
            if directory { try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false) }
            expectCoverageFailure(directory ? "manifest is not a regular file" : "manifest is missing") {
                _ = try CoverageScope.load(root: root)
            }
        }
    }

    @Test("Stale exclusions cannot hide undiscovered files")
    func staleExclusion() throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root, exclusions: "Sources/App/Missing.swift\tnative boundary\n")
            expectCoverageFailure("not a discovered production Swift source: Sources/App/Missing.swift") {
                _ = try CoverageScope.load(root: root)
            }
            expectCoverageFailure("Exclusion rationale: native boundary") {
                _ = try CoverageScope.load(root: root)
            }
        }
    }

    @Test("A source path with spaces stays unchanged")
    func spaces() throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root, sources: ["Sources/A name/A name.swift"])
            #expect(try CoverageScope.load(root: root).measured == ["Sources/A name/A name.swift"])
        }
    }

    @Test(
        "All control characters are rejected and escaped in discovered paths",
        arguments: ["\t", "\n", "\r", "\u{0001}", "\u{007F}"])
    func controls(character: String) throws {
        try withTemporaryDirectory { root in
            let source = "Sources/App/Bad\(character)Name.swift"
            try CoverageFixture.write(at: root, sources: [source])
            expectCoverageFailure("control character: \(String(reflecting: source))") {
                _ = try CoverageScope.load(root: root)
            }
        }
    }

    @Test(
        "A Sources root, nested directory, file or irrelevant file cannot be a symlink",
        arguments: [
            "Sources", "Sources/Nested", "Sources/App/Linked.swift", "Sources/Linked.txt",
        ])
    func sourceSymlinks(path: String) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            let external = root.appendingPathComponent("ExternalSources", isDirectory: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try Data("// external".utf8).write(to: external.appendingPathComponent("External.swift"))
            let link = root.appendingPathComponent(path)
            if path == "Sources" { try FileManager.default.removeItem(at: link) }
            let target = path.hasSuffix(".swift") ? external.appendingPathComponent("External.swift") : external
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            expectCoverageFailure("symbolic link") { _ = try CoverageScope.load(root: root) }
        }
    }

    @Test("Manifest file and parent symlinks are rejected", arguments: [false, true])
    func manifestSymlink(parent: Bool) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            let manifest = root.appendingPathComponent(CoverageFixture.manifest)
            let original = parent ? manifest.deletingLastPathComponent() : manifest
            let external = root.appendingPathComponent("external")
            try FileManager.default.moveItem(at: original, to: external)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: external)
            expectCoverageFailure("symbolic link") { _ = try CoverageScope.load(root: root) }
        }
    }

    @Test(
        "Manifest argument stays inside the package root",
        arguments: ["/tmp/exclusions.tsv", "../exclusions.tsv", "ci//scope.tsv"])
    func manifestArgument(path: String) throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root)
            #expect(throws: CoverageValidationError.self) { try CoverageScope.load(root: root, manifestPath: path) }
        }
    }

    @Test("Empty source directories classify without inventing measured files")
    func empty() throws {
        try withTemporaryDirectory { root in
            try CoverageFixture.write(at: root, sources: [])
            let scope = try CoverageScope.load(root: root)
            #expect(scope.all.isEmpty)
            #expect(scope.measured.isEmpty)
            #expect(scope.excluded.isEmpty)
        }
    }
}
