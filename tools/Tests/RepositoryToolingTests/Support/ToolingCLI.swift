import Foundation
import Testing

enum ToolingCLI {
    struct Result: Equatable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ arguments: [String], currentDirectory: URL) throws -> Result {
        try withTemporaryDirectory { outputDirectory in
            let stdoutURL = outputDirectory.appendingPathComponent("stdout")
            let stderrURL = outputDirectory.appendingPathComponent("stderr")
            try Data().write(to: stdoutURL)
            try Data().write(to: stderrURL)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdout.close()
                try? stderr.close()
            }

            let process = Process()
            process.executableURL = try executableURL()
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            return try Result(
                status: process.terminationStatus,
                stdout: String(contentsOf: stdoutURL, encoding: .utf8),
                stderr: String(contentsOf: stderrURL, encoding: .utf8)
            )
        }
    }

    private static func executableURL() throws -> URL {
        let executable = Bundle(for: ToolingTestsBundleMarker.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("littleswitch-tools")
        try #require(
            FileManager.default.isExecutableFile(atPath: executable.path),
            "SwiftPM must build littleswitch-tools beside the test runner: \(executable.path)"
        )
        return executable
    }
}

private final class ToolingTestsBundleMarker: NSObject {}
