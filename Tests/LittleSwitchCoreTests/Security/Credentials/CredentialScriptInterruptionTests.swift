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
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
        let interrupt = ProcessCredentialScriptRunner.InterruptBox()
        interrupt.interrupt()
        if escalated {
            interrupt.escalate()
            interrupt.interrupt()
        }
        interrupt.adopt(0)
        interrupt.adopt(process.processIdentifier)
        for _ in 0..<100 where process.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!process.isRunning)
        if !process.isRunning {
            #expect(process.terminationReason == .uncaughtSignal)
            #expect(process.terminationStatus == (escalated ? SIGKILL : SIGTERM))
        }
        interrupt.reachedTermination()
        interrupt.interrupt()
        interrupt.escalate()
        interrupt.adopt(process.processIdentifier)
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
