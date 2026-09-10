import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Codex application controller")
struct CodexApplicationControllerTests {
    @Test("Codex.app is preferred before ChatGPT compatibility fallbacks")
    func applicationCandidates() {
        let home = URL(filePath: "/Users/test")

        #expect(
            NSWorkspaceCodexController.applicationCandidates(homeDirectory: home).map(\.path) == [
                "/Applications/Codex.app",
                "/Applications/ChatGPT.app",
                "/Users/test/Applications/Codex.app",
                "/Users/test/Applications/ChatGPT.app",
            ]
        )
        #expect(NSWorkspaceCodexController.bundleIdentifier == "com.openai.codex")
    }
}
