import Foundation

/// Commands target only the named, opt-in repository lab. They never control the app.
enum MonitoringComposeLab {
    static func restoreLoki() async throws {
        try await command(["docker", "compose", "-f", "tools/monitoring/compose.yaml", "start", "loki"])
        try await command(["mise", "run", "--quiet", "tools:run", "--", "monitoring", "readiness"])
    }

    static func command(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { completed in
                if completed.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: CommandFailure(arguments: arguments, status: completed.terminationStatus))
                }
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private struct CommandFailure: Error {
        let arguments: [String]
        let status: Int32
    }
}
