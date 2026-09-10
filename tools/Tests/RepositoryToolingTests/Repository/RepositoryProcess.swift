import Foundation
import Testing

enum RepositoryProcess {
    struct Result: Equatable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func toolingExecutable() throws -> URL {
        let executable = Bundle(for: RepositoryTestsBundleMarker.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("littleswitch-tools")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        return executable
    }

    static func run(
        _ executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Result {
        try withTemporaryDirectory { output in
            let stdoutURL = output.appendingPathComponent("stdout")
            let stderrURL = output.appendingPathComponent("stderr")
            try Data().write(to: stdoutURL)
            try Data().write(to: stderrURL)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdout.close()
                try? stderr.close()
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            return try Result(
                status: process.terminationStatus,
                stdout: String(contentsOf: stdoutURL, encoding: .utf8),
                stderr: String(contentsOf: stderrURL, encoding: .utf8))
        }
    }
}

private final class RepositoryTestsBundleMarker: NSObject {}
