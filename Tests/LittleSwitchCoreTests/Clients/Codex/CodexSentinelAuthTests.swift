import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex sentinel auth")
struct CodexSentinelAuthTests {
    @Test("Installation creates the sentinel once with exact content and 0600")
    func installsOnce() throws {
        let fixture = try CodexSentinelFixture.make()
        defer { fixture.remove() }

        try fixture.sentinel.installIfAbsent()
        let first = try Data(contentsOf: fixture.authURL)
        #expect(CodexSentinelAuth.isManaged(first))
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.authURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)

        try Data(#"{"OPENAI_API_KEY":"user-edited","auth_mode":"apikey"}"#.utf8)
            .write(to: fixture.authURL)
        try fixture.sentinel.installIfAbsent()
        let second = try Data(contentsOf: fixture.authURL)
        #expect(!CodexSentinelAuth.isManaged(second))
    }

    @Test(
        "Recognition matches only exact sentinel content",
        arguments: [
            #"{"OPENAI_API_KEY":"little-switch-local-codex","auth_mode":"apikey"}"#
        ])
    func recognizesExactSentinel(content: String) throws {
        #expect(CodexSentinelAuth.isManaged(Data(content.utf8)))
    }

    @Test("Foreign or missing auth content is never managed")
    func rejectsForeignContent() {
        #expect(!CodexSentinelAuth.isManaged(nil))
        #expect(!CodexSentinelAuth.isManaged(Data()))
        #expect(!CodexSentinelAuth.isManaged(Data("not-json".utf8)))
        #expect(
            !CodexSentinelAuth.isManaged(
                Data(#"{"OPENAI_API_KEY":"sk-real","auth_mode":"apikey"}"#.utf8)
            )
        )
        #expect(
            !CodexSentinelAuth.isManaged(
                Data(
                    #"{"OPENAI_API_KEY":"little-switch-local-codex","auth_mode":"chatgpt","tokens":{}}"#
                        .utf8
                )
            )
        )
    }

    @Test("Removal touches only sentinel-owned files")
    func removesOnlySentinelFiles() throws {
        let fixture = try CodexSentinelFixture.make()
        defer { fixture.remove() }

        try fixture.sentinel.removeIfManaged()
        #expect(!FileManager.default.fileExists(atPath: fixture.authURL.path))

        try fixture.sentinel.installIfAbsent()
        try fixture.sentinel.removeIfManaged()
        #expect(!FileManager.default.fileExists(atPath: fixture.authURL.path))

        let foreign = Data(#"{"OPENAI_API_KEY":"sk-real","auth_mode":"apikey"}"#.utf8)
        try foreign.write(to: fixture.authURL)
        try fixture.sentinel.removeIfManaged()
        #expect(try Data(contentsOf: fixture.authURL) == foreign)
    }

    @Test("Activation installs the sentinel and restore removes it")
    func profileLifecycleInstallsAndRemoves() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let authURL = fixture.paths.config.deletingLastPathComponent().appending(path: "auth.json")

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        #expect(CodexSentinelAuth.isManaged(try Data(contentsOf: authURL)))

        try fixture.manager.restore()
        #expect(!FileManager.default.fileExists(atPath: authURL.path))
    }

    @Test("Restore keeps a real ChatGPT auth file untouched")
    func restoreKeepsForeignAuth() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let authURL = fixture.paths.config.deletingLastPathComponent().appending(path: "auth.json")
        let foreign = Data(#"{"OPENAI_API_KEY":"sk-real","auth_mode":"apikey"}"#.utf8)
        try foreign.write(to: authURL)

        try fixture.manager.activate(
            providers: fixture.providers,
            configuration: fixture.configuration
        )
        #expect(try Data(contentsOf: authURL) == foreign)
        try fixture.manager.restore()
        #expect(try Data(contentsOf: authURL) == foreign)
    }
}

private struct CodexSentinelFixture {
    let root: URL
    let authURL: URL
    let sentinel: CodexSentinelAuth

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "little-switch-codex-sentinel-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let authURL = root.appending(path: ".codex/auth.json")
        try FileManager.default.createDirectory(
            at: authURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return Self(
            root: root,
            authURL: authURL,
            sentinel: CodexSentinelAuth(configURL: root.appending(path: ".codex/config.toml"))
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
