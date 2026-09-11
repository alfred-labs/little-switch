import Foundation
import os

struct CodexProcessRunner: CodexProcessRunning {
    private struct Output {
        var data = Data()
        var stopped = false
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) throws -> Data {
        try run(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: CodexNativeCatalog.probeTimeout
        )
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        timeout: TimeInterval
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let output = OSAllocatedUnfairLock(initialState: Output())
        let drained = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            output.withLock { state in
                guard !state.stopped else { return }
                let available = handle.availableData
                if available.isEmpty {
                    state.stopped = true
                    handle.readabilityHandler = nil
                    drained.signal()
                } else {
                    state.data.append(available)
                }
            }
        }
        let exited = DispatchSemaphore(value: 0)
        // Observe termination before launching: even an immediately exiting
        // process must participate in the completion wait.
        process.terminationHandler = { _ in exited.signal() }
        defer {
            process.terminationHandler = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            // Serialize closing with any callback already in flight, so it
            // cannot read a handle that cleanup has just closed.
            output.withLock { state in
                state.stopped = true
                try? pipe.fileHandleForReading.close()
            }
            try? pipe.fileHandleForWriting.close()
        }
        let deadline = DispatchTime.now() + timeout
        try process.run()
        try? pipe.fileHandleForWriting.close()
        if exited.wait(timeout: deadline) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                // A stalled probe must not survive cleanup indefinitely when
                // its normal termination handler ignores SIGTERM.
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            throw CodexNativeCatalog.Error.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw CodexNativeCatalog.Error.nonZeroExit(process.terminationStatus)
        }
        // Termination does not imply that the final readability callback ran.
        // EOF shares the process deadline, including when an inherited writer
        // outlives the process, so draining cannot hang the caller forever.
        guard drained.wait(timeout: deadline) == .success else {
            throw CodexNativeCatalog.Error.timedOut
        }
        return output.withLock { $0.data }
    }
}
