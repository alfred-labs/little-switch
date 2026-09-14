import Foundation
import LittleSwitchCommon

public protocol ClaudeCodeCLIVersionReading: Sendable {
    func read() async throws -> ClaudeCodeCLIVersion?
}

/// Runs `<executable> --version` on a detached task and parses stdout.
public struct ProcessClaudeCodeCLIVersionReader: ClaudeCodeCLIVersionReading {
    private let executableURL: URL
    private let arguments: [String]

    public init(
        executableURL: URL = URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
        arguments: [String] = ["--version"]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    public func read() async throws -> ClaudeCodeCLIVersion? {
        let executableURL = self.executableURL
        let arguments = self.arguments
        let task = Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }
        // The detached closure never throws (errors become nil), so the
        // task's value is awaited without `try`.
        guard let output = await task.value else {
            return nil
        }
        return ClaudeCodeCLIVersion(parsing: output)
    }
}
