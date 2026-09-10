import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Homebrew release publication")
struct HomebrewReleaseTests {
    @Test("Publication commits only the verified cask and retries without duplicate commits")
    func updateAndRetry() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            let result = try fixture.run()
            #expect(result.status == 0, "\(result.stderr)")
            let expected = try HomebrewCask.update(
                HomebrewCaskTests.source, version: "1.2.3", checksum: fixture.checksum)
            #expect(try fixture.read("homebrew-alfred/Casks/littleswitch.rb") == expected)
            #expect(
                try fixture.git(fixture.tap, ["show", "HEAD:Casks/littleswitch.rb"])
                    == expected.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(try fixture.git(fixture.tap, ["status", "--porcelain"]).isEmpty)
            #expect(try fixture.pushes().isEmpty)
            let head = try fixture.git(fixture.tap, ["rev-parse", "HEAD"])
            let retry = try fixture.run("publish-homebrew.sh", ["--push"])
            #expect(retry.status == 0, "\(retry.stderr)")
            #expect(try fixture.git(fixture.tap, ["rev-parse", "HEAD"]) == head)
            #expect(try fixture.pushes() == ["push\t\(fixture.tap.path)\t\(head)"])
        }
    }

    @Test("Read-only preflight does not require a published release")
    func preflight() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try FileManager.default.removeItem(at: root.appendingPathComponent("release.json"))
            let before = try fixture.git(fixture.tap, ["rev-parse", "HEAD"])
            let result = try fixture.run("publish-homebrew.sh", ["--check"])
            #expect(result.status == 0, "\(result.stderr)")
            #expect(try fixture.git(fixture.tap, ["rev-parse", "HEAD"]) == before)
            #expect(try fixture.read("homebrew-alfred/Casks/littleswitch.rb") == HomebrewCaskTests.source)
            #expect(try fixture.read("calls").isEmpty)
        }
    }

    @Test("An inconsistent published digest leaves the tap unchanged")
    func badDigest() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try PublishedReleaseTests.metadata().write(to: root.appendingPathComponent("release.json"))
            let before = try fixture.git(fixture.tap, ["rev-parse", "HEAD"])
            let result = try fixture.run()
            #expect(result.status != 0)
            #expect(result.stderr.contains("SHA-256"))
            #expect(try fixture.git(fixture.tap, ["rev-parse", "HEAD"]) == before)
            #expect(try fixture.read("homebrew-alfred/Casks/littleswitch.rb") == HomebrewCaskTests.source)
        }
    }

    @Test(
        "Dirty repositories and every noncanonical push URL stop before uploading",
        arguments: ["dirty", "remote", "mixed"])
    func repositoryGuard(scenario: String) throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            if scenario == "dirty" {
                try fixture.write("homebrew-alfred/unrelated.txt", "user work")
            } else {
                if scenario == "mixed" {
                    _ = try fixture.git(
                        fixture.tap,
                        ["remote", "set-url", "--push", "origin", "git@github.com:alfred-labs/homebrew-alfred.git"])
                }
                _ = try fixture.git(
                    fixture.tap,
                    ["remote", "set-url", "--add", "--push", "origin", "git@github.com:someone-else/another-tap.git"])
            }
            let result = try fixture.run("publish-update.sh", ["--push"])
            #expect(result.status != 0)
            #expect(result.stderr.contains(scenario == "dirty" ? "must be clean" : "push URLs must point to"))
            #expect(try fixture.read("calls").isEmpty)
            #expect(try fixture.read("homebrew-alfred/Casks/littleswitch.rb") == HomebrewCaskTests.source)
            if scenario == "dirty" { #expect(try fixture.read("homebrew-alfred/unrelated.txt") == "user work") }
        }
    }

    @Test("An upload failure leaves both release repositories untouched")
    func failedUpload() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            let tapHead = try fixture.git(fixture.tap, ["rev-parse", "HEAD"])
            let releaseHead = try fixture.git(fixture.releases, ["rev-parse", "HEAD"])
            let result = try fixture.run("publish-update.sh", ["--push"], overrides: ["FAKE_UPLOAD_FAIL": "1"])
            #expect(result.status != 0)
            #expect(try fixture.git(fixture.tap, ["rev-parse", "HEAD"]) == tapHead)
            #expect(try fixture.git(fixture.releases, ["rev-parse", "HEAD"]) == releaseHead)
            #expect(try fixture.read("calls").split(separator: "\n").count == 1)
            #expect(try fixture.pushes().isEmpty)
        }
    }

    @Test("Successful publication marks Latest then pushes Sparkle before Homebrew", arguments: [false, true])
    func orderedPublication(push: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            let result = try fixture.run("publish-update.sh", push ? ["--push"] : [])
            #expect(result.status == 0, "\(result.stderr)")
            let firstCall = try #require(fixture.read("calls").split(separator: "\n").first)
            #expect(firstCall.hasPrefix("gh\trelease\tcreate\tv1.2.3\t"))
            #expect(firstCall.contains("\t--latest\t"))
            let repositories = try fixture.pushes().map { $0.split(separator: "\t")[1] }
            #expect(repositories.map(String.init) == (push ? [fixture.releases.path, fixture.tap.path] : []))
            #expect(
                try fixture.read("little-switch/appcast.xml").contains(
                    "<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>"))
            for repository in [fixture.tap, fixture.releases] {
                #expect(try fixture.git(repository, ["status", "--porcelain"]).isEmpty)
            }
        }
    }

    @Test("A Homebrew-only retry completes publication after a cask-stage failure")
    func homebrewResume() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try PublishedReleaseTests.metadata(overrides: ["assets": []]).write(
                to: root.appendingPathComponent("release.json"))
            let failed = try fixture.run("publish-update.sh", ["--push"])
            #expect(failed.status != 0)
            #expect(failed.stderr.contains("retry Homebrew"))
            let releaseHead = try fixture.git(fixture.releases, ["rev-parse", "HEAD"])
            #expect(try fixture.pushes() == ["push\t\(fixture.releases.path)\t\(releaseHead)"])
            try fixture.restoreMetadata()
            let retry = try fixture.run("publish-homebrew.sh", ["--push"])
            #expect(retry.status == 0, "\(retry.stderr)")
            #expect(try fixture.git(fixture.releases, ["rev-parse", "HEAD"]) == releaseHead)
            #expect(try fixture.pushes().count == 2)
        }
    }
}
