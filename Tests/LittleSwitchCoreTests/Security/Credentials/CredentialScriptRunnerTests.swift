import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Credential script runner")
struct CredentialScriptRunnerTests {
    /// Writes the script under test to a temporary file, as the editor's
    /// file picker would hand one over.
    private func makeScriptFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "credential-script-\(UUID().uuidString).sh")
        try Data(content.utf8).write(to: url)
        return url
    }

    @Test("The printed token is trimmed and stderr is captured")
    func trimsToken() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile("printf '  token-123 \\n' >&1; printf 'noise' >&2")
        defer { try? FileManager.default.removeItem(at: script) }

        let run = try await runner.run(scriptPath: script.path)

        #expect(run.token == "token-123")
        #expect(run.standardError == "noise")
    }

    @Test("A backgrounded child holding the pipe cannot wedge the run")
    func grandchildHoldingPipeStaysBounded() async throws {
        let runner = ProcessCredentialScriptRunner(
            timeout: 10,
            killGrace: 1,
            drainGrace: 0.5
        )
        // The disowned sleeper inherits stdout and holds it open far past
        // the script's own exit: without a bounded drain the run would wait
        // on it forever, wedging the save flow and the refresh loop.
        let script = try makeScriptFile("printf pipe-token; (sleep 30 &)")
        defer { try? FileManager.default.removeItem(at: script) }
        let box = RunBox()
        let task = Task {
            box.store(try? await runner.run(scriptPath: script.path))
        }

        var run: CredentialScriptRun?
        for _ in 0..<60 {
            if let value = box.value {
                run = value
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        task.cancel()

        #expect(run?.token == "pipe-token")
    }

    @Test("Homebrew directories lead the script PATH")
    func pathIncludesHomebrew() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile(
            "case \"$PATH\" in /opt/homebrew/bin:*) echo ready;; *) exit 9;; esac"
        )
        defer { try? FileManager.default.removeItem(at: script) }

        let run = try await runner.run(scriptPath: script.path)

        #expect(run.token == "ready")
    }

    @Test("A nonzero exit reports the status and the collapsed stderr tail")
    func exitFailure() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile("printf 'line1\\nline2\\n' >&2; exit 3")
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(
            throws: CredentialScriptError(reason: .exit(status: 3), standardError: "line1 line2")
        ) {
            _ = try await runner.run(scriptPath: script.path)
        }
    }

    @Test("Long stderr is bounded to a tail")
    func boundedStandardError() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile(
            "printf 'x%.0s' {1..600} >&2; printf ' END' >&2; exit 1"
        )
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(
            throws: CredentialScriptError(
                reason: .exit(status: 1),
                standardError: "…" + String(repeating: "x", count: 476) + " END"
            )
        ) {
            _ = try await runner.run(scriptPath: script.path)
        }
    }

    @Test("Empty or undecodable output produces no token")
    func emptyOutput() async throws {
        let runner = ProcessCredentialScriptRunner()
        let empty = try makeScriptFile("printf ''")
        defer { try? FileManager.default.removeItem(at: empty) }
        let undecodable = try makeScriptFile("printf '\\xff\\xfe'")
        defer { try? FileManager.default.removeItem(at: undecodable) }

        await #expect(
            throws: CredentialScriptError(reason: .emptyOutput, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: empty.path)
        }
        await #expect(
            throws: CredentialScriptError(reason: .emptyOutput, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: undecodable.path)
        }
    }

    @Test("A blank path is rejected before a process is spawned")
    func blankScriptPath() async throws {
        let runner = ProcessCredentialScriptRunner()

        await #expect(
            throws: CredentialScriptError(reason: .missingScriptPath, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: " \n ")
        }
    }

    @Test("A missing script file is rejected before a process is spawned")
    func missingScriptFile() async throws {
        let runner = ProcessCredentialScriptRunner()
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "credential-script-\(UUID().uuidString).sh")

        await #expect(
            throws: CredentialScriptError(reason: .missingScriptFile, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: missing.path)
        }
    }

    @Test("A script that never finishes times out and is terminated")
    func timeout() async throws {
        let runner = ProcessCredentialScriptRunner(timeout: 0.25)
        let script = try makeScriptFile("sleep 5")
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(
            throws: CredentialScriptError(reason: .timedOut, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: script.path)
        }
    }

    @Test("A SIGTERM-immune script is killed within the grace period")
    func trappedSignalEscalates() async throws {
        let runner = ProcessCredentialScriptRunner(timeout: 0.25, killGrace: 0.3)
        let script = try makeScriptFile("trap '' TERM; sleep 30")
        defer { try? FileManager.default.removeItem(at: script) }

        let started = ContinuousClock.now
        await #expect(
            throws: CredentialScriptError(reason: .timedOut, standardError: "")
        ) {
            // The orphaned `sleep` keeps the pipe open; only the escalation
            // lets the call return without waiting for it.
            _ = try await runner.run(scriptPath: script.path)
        }
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .seconds(10))
    }

    @Test("A shell that cannot be launched surfaces the spawn error")
    func launchFailure() async throws {
        let runner = ProcessCredentialScriptRunner(
            shellExecutable: "/nonexistent/credential-shell"
        )
        let script = try makeScriptFile("printf token")
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(throws: (any Error).self) {
            _ = try await runner.run(scriptPath: script.path)
        }
    }

    @Test("Cancelling the caller stops the script")
    func callerCancellation() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile("sleep 5")
        defer { try? FileManager.default.removeItem(at: script) }
        let task = Task {
            try await runner.run(scriptPath: script.path)
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("A script that kills itself is reported as interrupted")
    func interruptedScript() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile("kill -TERM $$")
        defer { try? FileManager.default.removeItem(at: script) }

        await #expect(
            throws: CredentialScriptError(reason: .interrupted, standardError: "")
        ) {
            _ = try await runner.run(scriptPath: script.path)
        }
    }

    @Test("An escalation armed after termination never signals")
    func escalationAfterTermination() async {
        let interrupt = ProcessCredentialScriptRunner.InterruptBox()
        interrupt.reachedTermination()
        interrupt.armEscalation(afterGrace: 0.05)

        // The disarmed watchdog completes without touching any process.
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test("The script environment carries HOME so token stores are reachable")
    func homeEnvironment() async throws {
        let runner = ProcessCredentialScriptRunner()
        let script = try makeScriptFile("[ -n \"$HOME\" ] || exit 7; basename \"$HOME\"")
        defer { try? FileManager.default.removeItem(at: script) }

        let run = try await runner.run(scriptPath: script.path)

        #expect(
            run.token == FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        )
    }

    @Test("Failure diagnostics name the reason and quote the stderr tail")
    func diagnostics() {
        #expect(
            CredentialScriptError(reason: .missingScriptPath, standardError: "")
                .errorDescription
                == "No credential script is chosen."
        )
        #expect(
            CredentialScriptError(reason: .missingScriptFile, standardError: "")
                .errorDescription
                == "The credential script file could not be found. "
                + "Re-choose it in the provider editor."
        )
        #expect(
            CredentialScriptError(reason: .emptyOutput, standardError: "")
                .errorDescription
                == "The credential script printed no token."
        )
        #expect(
            CredentialScriptError(reason: .timedOut, standardError: "")
                .errorDescription
                == "The credential script did not finish in time."
        )
        #expect(
            CredentialScriptError(reason: .exit(status: 2), standardError: "")
                .errorDescription
                == "The credential script exited with status 2."
        )
        #expect(
            CredentialScriptError(reason: .exit(status: 2), standardError: "vault down")
                .errorDescription
                == "The credential script exited with status 2. vault down"
        )
        #expect(
            CredentialScriptError(reason: .interrupted, standardError: "killed")
                .errorDescription
                == "The credential script was interrupted."
        )
    }
}

/// Collects one async result for polling, so a test can bound how long it
/// waits on a task that may never finish without hanging the suite.
private final class RunBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CredentialScriptRun?

    var value: CredentialScriptRun? {
        lock.withLock { stored }
    }

    func store(_ value: CredentialScriptRun?) {
        lock.withLock { stored = value }
    }
}
