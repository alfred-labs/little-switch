import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Codex TOML editor boundaries")
struct CodexTOMLEditorBoundaryTests {
    @Test("A probe-named table terminates owned provider replacement and removal")
    func probeNamedTableBoundary() throws {
        let following = "[__little_switch_probe]\nvalue = true"
        let original = """
            [model_providers.little-switch]
            name = "Stale"
            base_url = "http://127.0.0.1:1"
            wire_api = "responses"
            \(following)
            """

        let activated = try CodexTOMLEditor.activating(
            original,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(activated == activatedDocument(followedBy: following))
        #expect(try CodexTOMLEditor.removingOwnedProvider(from: original) == following)
    }

    @Test("An array table terminates owned provider replacement and removal")
    func arrayTableBoundary() throws {
        let following = "[[projects]]\npath = \"/tmp/project\""
        let original = """
            [model_providers.little-switch]
            name = "Stale"
            base_url = "http://127.0.0.1:1"
            wire_api = "responses"
            \(following)
            """

        let activated = try CodexTOMLEditor.activating(
            original,
            model: "managed",
            catalogPath: "/tmp/catalog.json"
        )
        #expect(activated == activatedDocument(followedBy: following))
        #expect(try CodexTOMLEditor.removingOwnedProvider(from: original) == following)
    }

    private func activatedDocument(followedBy following: String) -> String {
        """
        model = "managed"
        model_provider = "little-switch"
        model_catalog_json = "/tmp/catalog.json"
        model_reasoning_effort = "max"
        web_search = "live"

        [model_providers.little-switch]
        name = "LittleSwitch"
        base_url = "http://127.0.0.1:11436/v1/"
        wire_api = "responses"

        \(following)
        """
    }
}
