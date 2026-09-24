import Darwin
import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Credential script interruption")
struct CredentialScriptInterruptionTests {
    @Test("Signals requested before PID adoption reach only the adopted child", arguments: [false, true])
    func interruptedBeforeAdoption(escalated: Bool) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["5"]
        let terminated = AsyncTestGate()
        process.terminationHandler = { _ in
            Task { await terminated.open() }
        }
        try process.run()

        do {
            let interrupt = ProcessCredentialScriptRunner.InterruptBox()
            interrupt.interrupt()
            if escalated {
                interrupt.escalate()
                interrupt.interrupt()
            }
            interrupt.adopt(0)
            interrupt.adopt(process.processIdentifier)
            try await terminated.wait(timeout: .seconds(1), description: "the interrupted child to terminate")

            #expect(!process.isRunning)
            #expect(process.terminationReason == .uncaughtSignal)
            #expect(process.terminationStatus == (escalated ? SIGKILL : SIGTERM))
            interrupt.reachedTermination()
            interrupt.interrupt()
            interrupt.escalate()
            interrupt.adopt(process.processIdentifier)
            #expect(!process.isRunning)
            #expect(process.terminationStatus == (escalated ? SIGKILL : SIGTERM))
        } catch {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            // Cleanup must still await Foundation's termination delivery when the test was cancelled.
            let cleanup = Task {
                try await terminated.wait(timeout: .seconds(1), description: "the cleanup child to terminate")
            }
            do {
                try await cleanup.value
            } catch {
                Issue.record(error)
            }
            throw error
        }
    }

    @Test("Cancellation during the output drain prevents a completed script from returning its token")
    func cancelledDuringDrain() async throws {
        let script = FileManager.default.temporaryDirectory.appending(path: "credential-drain-\(UUID().uuidString).sh")
        try Data("printf token; (sleep 2 &)".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = ProcessCredentialScriptRunner(timeout: 5, drainGrace: 5)
        let task = Task { try await runner.run(scriptPath: script.path) }
        try await Task.sleep(for: .milliseconds(250))
        let started = ContinuousClock.now

        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}
