import Foundation
import Testing

@Suite("Monitoring command registration")
struct MonitoringCLITests {
    @Test("Monitoring exposes readiness and the synthetic probe without contacting the lab")
    func groupHelp() throws {
        let result = try ToolingCLI.run(["monitoring", "--help"], currentDirectory: .temporaryDirectory)
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("readiness"))
        #expect(result.stdout.contains("probe"))
    }

    @Test("Both async commands accept help and the common root option", arguments: ["readiness", "probe"])
    func commandHelp(command: String) throws {
        let result = try ToolingCLI.run(
            ["--root", "/private/tmp", "monitoring", command, "--help"], currentDirectory: .temporaryDirectory)
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("monitoring \(command)"))
    }

    @Test("Unexpected arguments fail before invoking HTTP", arguments: ["readiness", "probe"])
    func invalidArguments(command: String) throws {
        let result = try ToolingCLI.run(
            ["monitoring", command, "--invalid-fixture-option"], currentDirectory: .temporaryDirectory)
        #expect(result.status != 0)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("--invalid-fixture-option"))
    }
}
