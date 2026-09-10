import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Release command line")
struct ReleaseCLITests {
    @Test("Bump honors an explicit repository root and preserves files on invalid input")
    func bump() throws {
        try withTemporaryDirectory { root in
            let packaging = root.appendingPathComponent("packaging")
            let nested = root.appendingPathComponent("nested")
            for directory in [packaging, nested] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let file = packaging.appendingPathComponent("version.env")
            let initial = "# counter\nMARKETING_VERSION=1.2.3\nBUILD_NUMBER=999999999999999999999\n"
            try Data(initial.utf8).write(to: file)
            for version in ["1.2.2", "1.2.4\nBUILD_NUMBER=1", "1.2", ""] {
                let result = try ToolingCLI.run(
                    ["release", "bump", "--root", root.path, version], currentDirectory: nested)
                #expect(result.status != 0)
                #expect(result.stdout.isEmpty)
                #expect(try String(contentsOf: file, encoding: .utf8) == initial)
            }
            let result = try ToolingCLI.run(
                ["release", "--root", root.path, "bump", "1.3.0"], currentDirectory: nested)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout == "LittleSwitch 1.3.0 (build 1000000000000000000000)\n")
            #expect(
                try String(contentsOf: file, encoding: .utf8)
                    == "# counter\nMARKETING_VERSION=1.3.0\nBUILD_NUMBER=1000000000000000000000\n")
        }
    }

    @Test("Appcast CLI measures the DMG, supports notes and replacement, and writes safe XML")
    func appcast() throws {
        try withTemporaryDirectory { root in
            try Data(repeating: 120, count: 128).write(to: root.appendingPathComponent("LittleSwitch-0.1.1-arm64.dmg"))
            try Data("## Shipped\n\n- First note\n".utf8).write(to: root.appendingPathComponent("notes.md"))
            try Data("<rss>  <item>/download/v0.1.1/</item>\n <item>older</item></rss>".utf8).write(
                to: root.appendingPathComponent("appcast.xml"))
            let args = [
                "release", "appcast", "--version", "0.1.1", "--build", "2", "--dmg", "LittleSwitch-0.1.1-arm64.dmg",
                "--signature", "abc123", "--date", "Wed, 02 Sep 2026 18:00:00 +0000",
            ]
            let result = try ToolingCLI.run(
                args + [
                    "--notes-file", "notes.md", "--replace-version", "0.1.1", "--appcast", "appcast.xml", "--output",
                    "appcast.xml",
                ], currentDirectory: root)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.isEmpty)
            let document = try String(contentsOf: root.appendingPathComponent("appcast.xml"), encoding: .utf8)
            #expect(
                document
                    == SparkleAppcast.render(
                        .init(version: "0.1.1", build: "2", length: 128, signature: "abc123"),
                        publicationDate: "Wed, 02 Sep 2026 18:00:00 +0000",
                        description: "<h2>Shipped</h2>\n<ul><li>First note</li></ul>",
                        previous: " <item>older</item>"))
            let stdout = try ToolingCLI.run(args + ["--output", "-"], currentDirectory: root)
            #expect(stdout.status == 0, "\(stdout.stderr)")
            #expect(stdout.stdout.contains("length=\"128\""))
            for extra in [
                ["--notes-file", "notes.md", "--description", "other"], ["--dmg", "missing"],
                ["--output", "missing/out.xml"],
            ] {
                #expect(try ToolingCLI.run(args + extra, currentDirectory: root).status != 0)
            }
            #expect(
                try ToolingCLI.run(["release", "appcast", "--version", "0.1.1"], currentDirectory: root).status != 0)
        }
    }

    @Test("Homebrew preflight is read-only and the update requires verified published metadata")
    func homebrew() throws {
        try withTemporaryDirectory { root in
            let dmg = root.appendingPathComponent("LittleSwitch-1.2.3-arm64.dmg")
            let cask = root.appendingPathComponent("littleswitch.rb")
            try Data().write(to: dmg)
            try Data(HomebrewCaskTests.source.utf8).write(to: cask)
            let arguments = ["release", "homebrew", "--version", "1.2.3", "--dmg", dmg.path, "--cask", cask.path]
            #expect(try ToolingCLI.run(arguments + ["--check"], currentDirectory: root).status == 0)
            #expect(try String(contentsOf: cask, encoding: .utf8) == HomebrewCaskTests.source)
            #expect(try ToolingCLI.run(arguments, currentDirectory: root).status != 0)
            let checksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            let metadata = try PublishedReleaseTests.metadata(assetOverrides: [
                "digest": "sha256:" + checksum, "size": 0,
            ])
            try metadata.write(to: root.appendingPathComponent("release.json"))
            let result = try ToolingCLI.run(arguments + ["--release-metadata", "release.json"], currentDirectory: root)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(result.stdout.isEmpty)
            #expect(
                try String(contentsOf: cask, encoding: .utf8)
                    == HomebrewCask.update(HomebrewCaskTests.source, version: "1.2.3", checksum: checksum))
            #expect(
                try ToolingCLI.run(arguments + ["--dmg", "wrong-name.dmg", "--check"], currentDirectory: root).status
                    != 0)
        }
    }
}
