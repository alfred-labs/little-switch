import CryptoKit
import Foundation
import Testing

struct ReleaseFixture {
    let root: URL
    var environment: [String: String]
    let checksum: String

    var tap: URL { root.appendingPathComponent("homebrew-alfred") }
    var releases: URL { root.appendingPathComponent("little-switch") }

    init(root: URL) throws {
        self.root = root
        let artifact = Data("notarized DMG fixture".utf8)
        checksum = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
        environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment.merge([
            "PATH": root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Release Test", "GIT_AUTHOR_EMAIL": "release@example.invalid",
            "GIT_COMMITTER_NAME": "Release Test", "GIT_COMMITTER_EMAIL": "release@example.invalid",
            "LITTLE_SWITCH_RELEASE_TESTING": "1", "LITTLE_SWITCH_RELEASE_PROJECT_ROOT": root.path,
            "LITTLE_SWITCH_NOTARY_PROFILE": "model-switch-notary",
            "LITTLE_SWITCH_RELEASE_PLUTIL": root.appendingPathComponent("bin/plutil").path,
            "LITTLE_SWITCH_RELEASE_SPARKLE_KEY": root.appendingPathComponent("fixture-sparkle.key").path,
            "LITTLE_SWITCH_RELEASES_REPOSITORY": root.appendingPathComponent("little-switch").path,
            "LITTLE_SWITCH_HOMEBREW_REPOSITORY": root.appendingPathComponent("homebrew-alfred").path,
            "FAKE_ROOT": root.path, "FAKE_CLI": try RepositoryProcess.toolingExecutable().path,
        ]) { _, new in new }
        try write("homebrew-alfred/Casks/littleswitch.rb", HomebrewCaskTests.source)
        try write("little-switch/appcast.xml", "<rss><channel></channel></rss>\n")
        try write("packaging/release-notes.md", "## Changes\n\n- Release fixture\n")
        try write("packaging/version.env", "# build counter\nMARKETING_VERSION=1.2.3\nBUILD_NUMBER=12\n")
        try write("build/LittleSwitch.app/Contents/Info.plist", "fixture")
        try write("fixture-sparkle.key", "test fixture, not a real key")
        try write(".signing.env", "")
        try write("dist/LittleSwitch-1.2.3-arm64.dmg", "notarized DMG fixture")
        try write("dist/LittleSwitch-1.2.3-arm64.notary-result.json", "{\"status\":\"Accepted\"}")
        try write("calls", "")
        try restoreMetadata()
        for (directory, remote) in [(tap, "homebrew-alfred"), (releases, "little-switch")] {
            _ = try git(directory, ["init", "--initial-branch=main"])
            _ = try git(directory, ["add", "."])
            _ = try git(directory, ["commit", "-m", "fixture"])
            _ = try git(directory, ["remote", "add", "origin", "git@github.com:alfred-labs/\(remote).git"])
        }
        try tool("plutil", "case \"$2\" in CFBundleVersion) echo 12 ;; *) echo 1.2.3 ;; esac")
        try tool("mise", Self.mise)
        try tool("gh", Self.github)
        try tool("git", Self.git)
        try tool("node", "echo 'Node runtime must not be invoked' >&2; exit 90")
    }

    func write(_ path: String, _ contents: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func tool(_ name: String, _ body: String) throws {
        try write("bin/" + name, "#!/bin/sh\nset -eu\n" + body + "\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("bin/" + name).path)
    }

    func restoreMetadata() throws {
        let data = try PublishedReleaseTests.metadata(assetOverrides: ["digest": "sha256:" + checksum, "size": 21])
        try data.write(to: root.appendingPathComponent("release.json"))
    }

    func run(
        _ script: String = "publish-homebrew.sh",
        _ arguments: [String] = [],
        overrides: [String: String] = [:]
    ) throws -> RepositoryProcess.Result {
        try RepositoryProcess.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [RepositoryFixture.root().appendingPathComponent("tools/release/" + script).path] + arguments,
            directory: root,
            environment: environment.merging(overrides) { _, new in new })
    }

    func git(_ directory: URL, _ arguments: [String]) throws -> String {
        let result = try RepositoryProcess.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", directory.path] + arguments,
            directory: root,
            environment: environment)
        try #require(result.status == 0, "\(result.stderr)")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pushes() throws -> [String] {
        try read("calls").split(separator: "\n").filter { $0.hasPrefix("push\t") }.map(String.init)
    }

    private static let mise = #"""
        if [ "$1" = exec ]; then printf '%s\n' fixture-ed25519-signature; exit 0; fi
        while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done
        shift
        exec "$FAKE_CLI" "$@"
        """#

    private static let github = #"""
        printf 'gh' >> "$FAKE_ROOT/calls"
        for argument in "$@"; do printf '\t%s' "$argument" >> "$FAKE_ROOT/calls"; done
        printf '\n' >> "$FAKE_ROOT/calls"
        case "$1" in
            api) cat "$FAKE_ROOT/release.json" ;;
            release)
                [ "$2" = create ] || exit 2
                [ "${FAKE_UPLOAD_FAIL:-0}" = 0 ] || exit 7
                echo 'fixture uploaded'
                ;;
            *) exit 2 ;;
        esac
        """#

    private static let git = #"""
        [ "$1" = -C ] || exit 2
        case "$3" in
            push)
                head=$(/usr/bin/git -C "$2" rev-parse HEAD)
                printf 'push\t%s\t%s\n' "$2" "$head" >> "$FAKE_ROOT/calls"
                ;;
            rev-parse|symbolic-ref|status|diff|commit) exec /usr/bin/git "$@" ;;
            remote)
                [ "$4" = get-url ] || exit 2
                exec /usr/bin/git "$@"
                ;;
            *) echo 'Fixture rejects unexpected Git commands' >&2; exit 2 ;;
        esac
        """#
}
