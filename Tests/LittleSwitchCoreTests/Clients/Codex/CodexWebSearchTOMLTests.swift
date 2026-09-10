import Testing

@testable import LittleSwitchCore

@Suite("Codex web search TOML preservation")
struct CodexWebSearchTOMLTests {
    @Test("A saved assignment can restore a missing key with its original syntax")
    func restoreMissingAssignment() throws {
        let assignment = "\"web_search\" = 'cached' # original"
        let state = try CodexTOMLEditor.rootState("web_search", in: assignment, preservingAssignment: true)

        let restored = try CodexTOMLEditor.restoring("", states: ["web_search": state])

        #expect(restored == assignment + "\n")
    }

    @Test(
        "A saved assignment cannot change another key or restore an inconsistent value",
        arguments: [
            "model = 'other'\nweb_search = 'cached'",
            "web_search = 'live'",
        ])
    func invalidSavedAssignment(assignment: String) throws {
        let state = CodexRootStringState(wasPresent: true, value: "cached", originalAssignment: assignment)

        #expect(throws: CodexTOMLEditor.Error.unsupportedRootSyntax("web_search")) {
            try CodexTOMLEditor.restoring("web_search = 'live'", states: ["web_search": state])
        }
    }

    @Test("Unsupported multiline search assignments are rejected before capture")
    func multilineAssignment() {
        let original = "web_search = \"\"\"\ncached\n\"\"\""

        #expect(throws: CodexTOMLEditor.Error.unsupportedRootSyntax("web_search")) {
            try CodexTOMLEditor.rootState("web_search", in: original, preservingAssignment: true)
        }
    }
}
