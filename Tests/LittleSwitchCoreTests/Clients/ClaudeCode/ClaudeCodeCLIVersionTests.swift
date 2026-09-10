import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Claude Code CLI version")
struct ClaudeCodeCLIVersionTests {
    @Test("parses observed --version output shapes")
    func parsing() {
        #expect(
            ClaudeCodeCLIVersion(parsing: "2.1.259 (Claude Code)\n")?.rawValue
                == "2.1.259"
        )
        #expect(ClaudeCodeCLIVersion(parsing: "2.1.259")?.rawValue == "2.1.259")
        #expect(ClaudeCodeCLIVersion(parsing: "  \n") == nil)
    }

    @Test("revalidation is required exactly on version change or first run")
    func revalidation() {
        let current = ClaudeCodeCLIVersion(rawValue: "2.1.259")
        #expect(current.requiresRevalidation(previouslyValidated: nil))
        #expect(
            !current.requiresRevalidation(
                previouslyValidated: ClaudeCodeCLIVersion(rawValue: "2.1.259")
            )
        )
        #expect(
            current.requiresRevalidation(
                previouslyValidated: ClaudeCodeCLIVersion(rawValue: "2.1.260")
            )
        )
    }

    @Test("reader executes a process and parses its output")
    func reader() async throws {
        let reader = ProcessClaudeCodeCLIVersionReader(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["2.1.259 (Claude Code)"]
        )
        let version = try await reader.read()
        #expect(version?.rawValue == "2.1.259")
    }

    @Test("reader returns nil when the executable is missing")
    func readerMissingExecutable() async throws {
        let reader = ProcessClaudeCodeCLIVersionReader(
            executableURL: URL(fileURLWithPath: "/nonexistent/claude")
        )
        let version = try await reader.read()
        #expect(version == nil)
    }
}
