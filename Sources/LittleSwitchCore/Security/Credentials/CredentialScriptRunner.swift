import Foundation
import os

/// Why a credential script failed to produce a token.
package enum CredentialScriptFailureReason: Equatable, Sendable {
    case missingScriptPath
    case missingScriptFile
    case emptyOutput
    case timedOut
    case exit(status: Int32)
    case interrupted
}

/// A credential script run failed. `standardError` carries a bounded tail of
/// the script's stderr so diagnosis stays possible without logging forever.
package struct CredentialScriptError: Error, Equatable, Sendable, LocalizedError {
    package let reason: CredentialScriptFailureReason
    package let standardError: String

    package init(reason: CredentialScriptFailureReason, standardError: String) {
        self.reason = reason
        self.standardError = standardError
    }

    package var errorDescription: String? {
        let prefix: String
        switch reason {
        case .missingScriptPath:
            return "No credential script is chosen."
        case .missingScriptFile:
            return "The credential script file could not be found. Re-choose it in the provider editor."
        case .emptyOutput:
            return "The credential script printed no token."
        case .timedOut:
            return "The credential script did not finish in time."
        case .exit(let status):
            prefix = "The credential script exited with status \(status)."
        case .interrupted:
            return "The credential script was interrupted."
        }
        guard !standardError.isEmpty else {
            return prefix
        }
        return "\(prefix) \(standardError)"
    }
}

/// What a successful credential script run produced: the token for the
/// keychain and the bounded stderr tail for the editor's output pane.
public struct CredentialScriptRun: Equatable, Sendable {
    public let token: String
    public let standardError: String

    public init(token: String, standardError: String) {
        self.token = token
        self.standardError = standardError
    }
}

/// Produces a provider credential by running a user-authored shell script and
/// taking its standard output.
///
/// The script runs unsandboxed on purpose: common token sources perform real
/// logins — `vault login -method=oidc` opens the default browser, `gh auth
/// login` prompts — and must behave exactly as when the user runs them from a
/// terminal. Output is consumed through pipes, never the terminal.
public protocol CredentialScriptRunning: Sendable {
    func run(scriptPath: String) async throws -> CredentialScriptRun
}

public struct ProcessCredentialScriptRunner: CredentialScriptRunning {
    /// Homebrew prefixes first so scripts find `vault`, `gh`, `jq`, and
    /// friends even though a bundled app does not inherit a login shell PATH.
    public static let scriptPath =
        "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    public var timeout: TimeInterval
    /// Grace between the SIGTERM issued at timeout or cancellation and the
    /// SIGKILL escalation that follows it.
    public var killGrace: TimeInterval
    /// How long a finished script's output pipes may take to drain once the
    /// process has exited. A backgrounded child inherits the pipes and can
    /// hold them open long after the script itself is done; the token is
    /// already complete by then, so the wait is bounded instead of forever.
    public var drainGrace: TimeInterval
    /// The shell that executes the chosen script file. Tests point it at a
    /// missing binary so launch failures can be exercised deterministically.
    let shellExecutable: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        timeout: TimeInterval = 600,
        killGrace: TimeInterval = 2,
        drainGrace: TimeInterval = 2,
        shellExecutable: String = "/bin/bash",
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.timeout = timeout
        self.killGrace = killGrace
        self.drainGrace = drainGrace
        self.shellExecutable = shellExecutable
        self.fileExists = fileExists
    }

    public func run(scriptPath: String) async throws -> CredentialScriptRun {
        let trimmedPath = scriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw CredentialScriptError(reason: .missingScriptPath, standardError: "")
        }
        guard fileExists(trimmedPath) else {
            throw CredentialScriptError(reason: .missingScriptFile, standardError: "")
        }

        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellExecutable)
        process.arguments = [trimmedPath]
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = Self.scriptEnvironment

        let interrupt = InterruptBox()
        return try await withTaskCancellationHandler {
            try await runAndCollect(
                process,
                interrupt: interrupt,
                standardOutput: standardOutput,
                standardError: standardError
            )
        } onCancel: {
            interrupt.interrupt()
        }
    }

    private func runAndCollect(
        _ process: Process,
        interrupt: InterruptBox,
        standardOutput: Pipe,
        standardError: Pipe
    ) async throws -> CredentialScriptRun {
        // Pipe reads block until every inherited write end closes, so they
        // cannot be implicitly awaited at scope exit: a timed-out run would
        // then hang on an orphaned grandchild holding the pipe. They run in
        // free-standing, cancellation-aware tasks (a cancelled read ends at
        // whatever arrived); on non-finished outcomes they are cancelled
        // outright, and a finished run waits at most `drainGrace` for them —
        // a backgrounded child can hold the pipes open forever after the
        // script itself has exited.
        let outputTask = Task<Data?, Never> {
            await Self.readAll(from: standardOutput.fileHandleForReading)
        }
        let errorTask = Task<Data?, Never> {
            await Self.readAll(from: standardError.fileHandleForReading)
        }

        let termination = await withTimeoutOrCancellation(
            seconds: timeout,
            interrupt: interrupt,
            killGrace: killGrace
        ) {
            try await Self.runAndWait(process, interrupt: interrupt)
        }
        switch termination {
        case .finished:
            break
        case .timedOut:
            outputTask.cancel()
            errorTask.cancel()
            throw CredentialScriptError(reason: .timedOut, standardError: "")
        case .failed(let error):
            // The launch failed, so no child ever existed to close the pipe
            // write ends: close them here or the reads above block forever.
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            outputTask.cancel()
            errorTask.cancel()
            throw error
        case .cancelled:
            outputTask.cancel()
            errorTask.cancel()
            throw CancellationError()
        }
        try Task.checkCancellation()

        // The watchdog bounds the drain: whatever arrived by the deadline is
        // the script's complete output (it has exited), and anything a
        // surviving grandchild writes later was never part of the token.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(drainGrace))
            outputTask.cancel()
            errorTask.cancel()
        }
        let outputData = await outputTask.value
        let errorData = await errorTask.value
        watchdog.cancel()

        let outputText = outputData.flatMap { String(data: $0, encoding: .utf8) }
        let output = outputText?.trimmingCharacters(in: .whitespacesAndNewlines)

        let errorText = Self.boundedTail(
            errorData.flatMap { String(data: $0, encoding: .utf8) }
        )

        let terminationStatus = process.terminationStatus
        guard terminationStatus == 0 else {
            let reason: CredentialScriptFailureReason =
                process.terminationReason == .uncaughtSignal
                ? .interrupted
                : .exit(status: terminationStatus)
            throw CredentialScriptError(reason: reason, standardError: errorText)
        }
        guard let token = output, !token.isEmpty else {
            throw CredentialScriptError(reason: .emptyOutput, standardError: errorText)
        }
        return CredentialScriptRun(token: token, standardError: errorText)
    }

    private enum ScriptProcessOutcome {
        case finished
        case timedOut
        case cancelled
        case failed(any Error)
    }

    /// Races "run started and terminated" against the timeout. Caller
    /// cancellation is observed through the child tasks: a cancelled sleep or
    /// wait reports `.cancelled`, and the `onCancel` handler has already
    /// signalled the process by then. Run failures surface as `.failed` so a
    /// script that cannot start is not mistaken for a lost termination.
    private func withTimeoutOrCancellation(
        seconds: TimeInterval,
        interrupt: InterruptBox,
        killGrace: TimeInterval,
        operation: @escaping @Sendable () async throws -> Void
    ) async -> ScriptProcessOutcome {
        await withTaskGroup(of: ScriptProcessOutcome.self) { group in
            group.addTask {
                do {
                    try await operation()
                } catch {
                    return .failed(error)
                }
                return Task.isCancelled ? .cancelled : .finished
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return .cancelled
                }
                return .timedOut
            }
            // Seeding with `.cancelled` keeps an empty group from crashing
            // the run; in practice the first completed child always wins.
            var outcome = ScriptProcessOutcome.cancelled
            for await result in group {
                outcome = result
                break
            }
            group.cancelAll()
            // Leaving the group implicitly awaits the run child, which stays
            // parked in its termination continuation until the script dies —
            // so the timeout and cancellation signals must fire here, before
            // that await, or the outcome waits out the script's whole
            // natural lifetime.
            switch outcome {
            case .timedOut, .cancelled:
                interrupt.interrupt()
                interrupt.armEscalation(afterGrace: killGrace)
            case .finished, .failed:
                break
            }
            return outcome
        }
    }

    /// Reads the handle to EOF in a cancellation-aware way: task
    /// cancellation ends the read with whatever arrived by then, so a
    /// backgrounded child holding the pipe cannot wedge the reader forever.
    private static func readAll(from handle: FileHandle) async -> Data? {
        let data = await CredentialScriptPipeReader(handle: handle).read()
        return data.isEmpty ? nil : data
    }

    /// Installs the termination handler before `run()` so a script that exits
    /// immediately can never slip past the observer, and returns once the
    /// process terminates.
    private static func runAndWait(
        _ process: Process,
        interrupt: InterruptBox
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                interrupt.reachedTermination()
                continuation.resume()
            }
            do {
                try process.run()
                interrupt.adopt(process.processIdentifier)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Serializes the process identifier and the first termination delivery so
    /// cancellation before `run()` cannot signal an unowned PID and a started
    /// process is always terminated exactly once.
    final class InterruptBox: Sendable {
        private struct State {
            var processIdentifier: Int32 = 0
            var terminated = false
            var escalation: Task<Void, Never>?
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        init() {}

        func adopt(_ processIdentifier: Int32) {
            state.withLock { state in
                state.processIdentifier = processIdentifier
            }
        }

        func reachedTermination() {
            state.withLock { state in
                state.terminated = true
                // A SIGTERM that already worked must never be followed by a
                // late SIGKILL: disarm the watchdog so a recycled PID cannot
                // receive it either.
                state.escalation?.cancel()
                state.escalation = nil
            }
        }

        /// Arms the SIGKILL watchdog. A termination observed first — the
        /// SIGTERM won the race — leaves it disarmed.
        func armEscalation(afterGrace grace: TimeInterval) {
            let watchdog = Task.detached { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(grace))
                } catch {
                    return
                }
                self?.escalate()
            }
            state.withLock { state in
                guard !state.terminated else {
                    watchdog.cancel()
                    return
                }
                state.escalation = watchdog
            }
        }

        func interrupt() {
            signalChild(SIGTERM)
        }

        func escalate() {
            signalChild(SIGKILL)
        }

        private func signalChild(_ signal: Int32) {
            let processIdentifier = state.withLock { state -> Int32? in
                state.terminated ? nil : state.processIdentifier
            }
            if let processIdentifier, processIdentifier > 0 {
                kill(processIdentifier, signal)
            }
        }
    }

    static func boundedTail(_ text: String?) -> String {
        guard let text, !text.isEmpty else {
            return ""
        }
        let collapsed =
            text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard collapsed.count > 480 else {
            return collapsed
        }
        return "…" + String(collapsed.suffix(480))
    }

    static var scriptEnvironment: [String: String] {
        var environment = [
            "PATH": scriptPath,
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": NSTemporaryDirectory(),
        ]
        let parent = ProcessInfo.processInfo.environment
        for name in ["USER", "LOGNAME", "SHELL"] {
            if let value = parent[name] {
                environment[name] = value
            }
        }
        return environment
    }
}
