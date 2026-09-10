import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex profile live web search")
struct CodexProfileWebSearchTests {
    @Test(
        "Activation requests live search and repeated activation preserves the original mode",
        arguments: [nil, "cached", "indexed", "disabled", "live"] as [String?]
    )
    func activationAndRestore(originalMode: String?) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let original =
            (originalMode.map { "web_search = \"\($0)\"\n" } ?? "")
            + "approval_policy = \"on-request\"\n\n[features]\nshell_tool = true\n"
        try Data(original.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)

        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("web_search", in: managed) == "live")
        let journal = try rootValues(fixture)

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        #expect(try rootValues(fixture) == journal)

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Invalid search mode types fail before any managed file is written")
    func invalidModeHasNoSideEffects() throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let original = Data("web_search = false\n".utf8)
        try original.write(to: fixture.paths.config)

        #expect(throws: CodexTOMLEditor.Error.nonStringRootValue("web_search")) {
            try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        }

        #expect(try Data(contentsOf: fixture.paths.config) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.catalog.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.restoreState.path))
    }

    @Test(
        "A profile whose managed search mode changes is no longer current",
        arguments: [nil, "\"cached\"", "\"indexed\"", "\"disabled\"", "false"] as [String?]
    )
    func modeDrift(replacement: String?) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)
        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        let drifted = managed.replacingOccurrences(
            of: "web_search = \"live\"\n", with: replacement.map { "web_search = \($0)\n" } ?? ""
        )
        try Data(drifted.utf8).write(to: fixture.paths.config)

        #expect(try !fixture.manager.isActive(providers: fixture.providers, configuration: fixture.configuration))
    }

    @Test(
        "Assignment-like text inside instructions is never edited as root configuration",
        arguments: ["'''", "\"\"\""], [false, true]
    )
    func assignmentLikeInstructions(delimiter: String, hasRootMode: Bool) throws {
        let fixture = try CodexProfileFixture.make()
        defer { fixture.remove() }
        let original = """
            developer_instructions = \(delimiter)
            Keep this example intact:
            web_search = "cached"
            model_provider = "example"
            \(delimiter)
            """ + (hasRootMode ? "\nweb_search = 'disabled' # original\n" : "\n")
        try Data(original.utf8).write(to: fixture.paths.config)

        try fixture.manager.activate(providers: fixture.providers, configuration: fixture.configuration)

        let managed = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(try CodexTOMLEditor.rootString("web_search", in: managed) == "live")
        #expect(
            try CodexTOMLEditor.rootString("developer_instructions", in: managed)
                == CodexTOMLEditor.rootString("developer_instructions", in: original)
        )

        try fixture.manager.restore()

        let restored = try String(contentsOf: fixture.paths.config, encoding: .utf8)
        #expect(
            restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func rootValues(_ fixture: CodexProfileFixture) throws -> [String: CodexRootStringState] {
        try JSONDecoder().decode(
            RootValues.self,
            from: Data(contentsOf: fixture.paths.restoreState)
        ).rootValues
    }
}

private struct RootValues: Decodable {
    let rootValues: [String: CodexRootStringState]
}
