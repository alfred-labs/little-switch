import Testing

@testable import LittleSwitchCore

@Suite("Codex concurrency original state")
struct CodexAgentConcurrencyStateTests {
    @Test("Repeated activation preserves deliberately absent original fields")
    func absentOriginalFields() throws {
        let initial = try CodexAgentConcurrencyEditor.activating(
            "", maximumConcurrentThreadsPerSession: 4
        )

        let repeated = try CodexAgentConcurrencyEditor.activating(
            initial.text, maximumConcurrentThreadsPerSession: 4, state: initial.state
        )

        #expect(repeated.state == initial.state)
        #expect(repeated.text == initial.text)
    }
}
