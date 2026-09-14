import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

/// Returns queued results in order, repeating the last one once the queue
/// runs dry, and records every script it was handed.
private final class ScriptedRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CredentialScriptRun, any Error>]
    private var calls: [String] = []

    init(results: [Result<CredentialScriptRun, any Error>]) {
        self.results = results
    }

    static func success(
        _ token: String,
        standardError: String = ""
    ) -> Self {
        Self(results: [
            .success(CredentialScriptRun(token: token, standardError: standardError))
        ])
    }

    var callCount: Int {
        lock.withLock { calls.count }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        let result = lock.withLock { () -> Result<CredentialScriptRun, any Error> in
            calls.append(scriptPath)
            if results.count > 1 {
                return results.removeFirst()
            }
            return results[0]
        }
        switch result {
        case .success(let run):
            return run
        case .failure(let error):
            throw error
        }
    }
}

/// Records requested durations and holds each caller until released.
private final class BlockingSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private(set) var durations: [TimeInterval] = []

    var recordedDurations: [TimeInterval] {
        lock.withLock { durations }
    }

    func release() {
        lock.withLock { open = true }
    }

    func hold(seconds: TimeInterval) async throws {
        lock.withLock { durations.append(seconds) }
        while true {
            if lock.withLock({ open }) {
                return
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Suite("Credential refresher")
struct CredentialRefresherTests {
    private func makeRefresher(
        store: MemorySecretStore = MemorySecretStore(),
        runner: any CredentialScriptRunning,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
            try await Task.sleep(for: .milliseconds(10))
        }
    ) -> CredentialRefresher {
        CredentialRefresher(secretStore: store, runner: runner, sleep: sleep)
    }

    @Test("The loop refreshes immediately, then after each interval")
    func loopCadence() async throws {
        let store = MemorySecretStore()
        let runner = ScriptedRunner.success("token")
        let sleep = BlockingSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.hold(seconds: seconds)
        }
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "first immediate run") {
            (runner.callCount == 1) ? true : nil
        }
        sleep.release()
        // Once released, the fake sleep returns immediately, so the loop
        // refreshes repeatedly; wait for at least the second pass.
        _ = try await eventually(description: "run after the interval") {
            (runner.callCount >= 2) ? true : nil
        }
        #expect(try store.read(providerID: providerID) == "token")
        await refresher.cancel(providerID: providerID)
    }

    @Test("Without immediate the loop sleeps a full interval before running")
    func delayedFirstRun() async throws {
        let store = MemorySecretStore()
        let runner = ScriptedRunner.success("token")
        let sleep = BlockingSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.hold(seconds: seconds)
        }
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )

        try await Task.sleep(for: .milliseconds(120))
        #expect(runner.callCount == 0)
        #expect(sleep.recordedDurations == [3_600])
        await refresher.cancel(providerID: providerID)
    }

    @Test("Sub-minute intervals clamp to one minute")
    func intervalClamp() async throws {
        let store = MemorySecretStore()
        let sleep = BlockingSleep()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner.success("token")
        ) { seconds in
            try await sleep.hold(seconds: seconds)
        }
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 0.5,
            immediate: false,
            scriptPath: "echo token"
        )

        try await Task.sleep(for: .milliseconds(120))
        #expect(sleep.recordedDurations == [60])
        await refresher.cancel(providerID: providerID)
    }

    @Test("A failed run records its message and a later success clears it")
    func failureThenRecovery() async throws {
        let store = MemorySecretStore()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner(
                results: [
                    .failure(
                        CredentialScriptError(reason: .exit(status: 2), standardError: "vault down")
                    ),
                    .success(CredentialScriptRun(token: "fresh", standardError: "")),
                ]
            )
        )
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        let message = try await eventually(description: "failure message") {
            await refresher.failureMessages()[providerID]
        }
        #expect(message == "The credential script exited with status 2. vault down")

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "cleared failure message") {
            (await refresher.failureMessages()[providerID] == nil) ? true : nil
        }
        #expect(try store.read(providerID: providerID) == "fresh")
        await refresher.cancel(providerID: providerID)
    }

    @Test("A missing script records the missing-script failure")
    func missingScriptFailure() async throws {
        let refresher = makeRefresher(runner: ScriptedRunner.success("token"))
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: ""
        )

        let message = try await eventually(description: "missing script message") {
            await refresher.failureMessages()[providerID]
        }
        #expect(message == "No credential script is chosen.")
        await refresher.cancel(providerID: providerID)
    }

    @Test("Rescheduling replaces the cadence")
    func rescheduleReplacesCadence() async throws {
        let store = MemorySecretStore()
        let runner = ScriptedRunner.success("token")
        let sleep = BlockingSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.hold(seconds: seconds)
        }
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )
        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )

        _ = try await eventually(description: "run after reschedule") {
            (runner.callCount == 1) ? true : nil
        }
        await refresher.cancel(providerID: providerID)
    }

    @Test("An error without a message falls back to its plain description")
    func plainErrorFallback() async throws {
        let store = MemorySecretStore()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner(results: [.failure(PlainRefreshError())])
        )
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        let message = try await eventually(description: "plain error message") {
            await refresher.failureMessages()[providerID]
        }
        #expect(message == String(describing: PlainRefreshError()))
        await refresher.cancel(providerID: providerID)
    }

    @Test("The default sleep drives the loop between runs")
    func defaultSleepCadence() async throws {
        let store = MemorySecretStore()
        let runner = ScriptedRunner.success("token")
        let refresher = CredentialRefresher(secretStore: store, runner: runner)
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "immediate run under the default sleep") {
            (runner.callCount == 1) ? true : nil
        }
        #expect(try store.read(providerID: providerID) == "token")
        // The loop parks in the real interval sleep right after the run;
        // give it a beat to enter the default closure before cancelling.
        try await Task.sleep(for: .milliseconds(150))
        await refresher.cancel(providerID: providerID)
    }

    @Test("Cancel all stops every loop")
    func cancelAllStopsLoops() async throws {
        let store = MemorySecretStore()
        let runner = ScriptedRunner.success("token")
        let sleep = BlockingSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.hold(seconds: seconds)
        }
        let firstID = UUID()
        let secondID = UUID()

        await refresher.schedule(
            providerID: firstID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )
        await refresher.schedule(
            providerID: secondID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )
        await refresher.cancelAll()

        // Releasing the held sleep is the assertion: a cancelled loop breaks
        // out of the sleep instead of running the script, so any run after
        // this point means cancelAll failed.
        sleep.release()
        try await Task.sleep(for: .milliseconds(150))
        #expect(runner.callCount == 0)
    }

    @Test("Cancelling a provider clears its recorded failure")
    func cancelClearsOutcome() async throws {
        let store = MemorySecretStore()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner(
                results: [.failure(CredentialScriptError(reason: .exit(status: 1), standardError: ""))]
            )
        )
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "failure message") {
            await refresher.failureMessages()[providerID]
        }

        await refresher.cancel(providerID: providerID)
        #expect(await refresher.failureMessages().isEmpty)
    }

    @Test("The save flow's outcome recording clears a stale failure")
    func recordedOutcomeReplacesFailure() async throws {
        let store = MemorySecretStore()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner(
                results: [.failure(CredentialScriptError(reason: .exit(status: 1), standardError: ""))]
            )
        )
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "failure message") {
            await refresher.failureMessages()[providerID]
        }

        await refresher.record(
            providerID: providerID,
            outcome: CredentialRefreshOutcome(kind: .refreshed)
        )
        #expect(await refresher.failureMessages().isEmpty)
    }

    @Test("The last run's stderr surfaces for successes, failures, and cancellations")
    func lastScriptOutputsTrackRuns() async throws {
        let store = MemorySecretStore()
        let refresher = makeRefresher(
            store: store,
            runner: ScriptedRunner.success("token", standardError: "Success! Logged in.")
        )
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        let output = try await eventually(description: "successful run output") {
            await refresher.lastScriptOutputs()[providerID]
        }
        #expect(output == "Success! Logged in.")

        // A cancelled provider carries no output: nothing replays in the
        // editor for a loop that no longer exists.
        await refresher.cancel(providerID: providerID)
        #expect(await refresher.lastScriptOutputs().isEmpty)
    }
}
