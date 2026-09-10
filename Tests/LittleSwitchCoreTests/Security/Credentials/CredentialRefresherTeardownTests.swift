import Foundation
import Testing

@testable import LittleSwitchCore

/// Blocks every run until the gate opens, ignoring task cancellation so
/// an in-flight run can be observed outliving its cancelled loop.
private final class GatedRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var gateOpen = false
    private var count = 0

    var callCount: Int {
        lock.withLock { count }
    }

    func open() {
        lock.withLock { gateOpen = true }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        lock.withLock { count += 1 }
        while true {
            if lock.withLock({ gateOpen }) {
                return CredentialScriptRun(token: "gated", standardError: "")
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Throws `CancellationError` as soon as its task is cancelled, recording
/// that it did — the shape a runner that honours cancellation presents.
private final class CancellingRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var cancelled = false

    var callCount: Int {
        lock.withLock { count }
    }

    var threwCancellation: Bool {
        lock.withLock { cancelled }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        lock.withLock { count += 1 }
        while !lock.withLock({ cancelled }) {
            do {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                lock.withLock { cancelled = true }
                throw error
            }
        }
        return CredentialScriptRun(token: "cancelled", standardError: "")
    }
}

/// Throws a plain error once opened, ignoring cancellation — the shape of a
/// run whose failure was already decided while its loop got torn down
/// underneath it (an exited script, a lost pipe).
private final class LateFailingRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var count = 0

    var callCount: Int {
        lock.withLock { count }
    }

    func open() {
        lock.withLock { opened = true }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        lock.withLock { count += 1 }
        while true {
            if lock.withLock({ opened }) {
                throw PlainRefreshError()
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Returns the first sleep call immediately, then holds every later caller
/// until released — so a replacement loop can be observed parking between
/// passes while an earlier run is still in flight.
private final class FirstThenHeldSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var count = 0

    var callCount: Int {
        lock.withLock { count }
    }

    func release() {
        lock.withLock { open = true }
    }

    func sleep(seconds: TimeInterval) async throws {
        let isFirst = lock.withLock { () -> Bool in
            count += 1
            return count == 1
        }
        if isFirst {
            return
        }
        while true {
            if lock.withLock({ open }) {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// An error with no `LocalizedError` conformance, so failure messages must
/// fall back to its plain description.
struct PlainRefreshError: Error {}

/// How the refresher behaves when a run outlives its loop: cancellation,
/// stale tokens, and late failures must stay silent instead of resurrecting
/// state for a provider whose refresh cycle is gone.
@Suite("Credential refresher teardown")
struct CredentialRefresherTeardownTests {
    private func makeRefresher(
        store: MemorySecretStore = MemorySecretStore(),
        runner: any CredentialScriptRunning,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
            try await Task.sleep(for: .milliseconds(10))
        }
    ) -> CredentialRefresher {
        CredentialRefresher(secretStore: store, runner: runner, sleep: sleep)
    }

    @Test("An in-flight run blocks the replacement loop's first pass")
    func overlappingRunsAreSkipped() async throws {
        let store = MemorySecretStore()
        let runner = GatedRunner()
        let sleep = FirstThenHeldSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.sleep(seconds: seconds)
        }
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "gated run entered") {
            (runner.callCount == 1) ? true : nil
        }

        // The replacement loop is not immediate, so it sleeps first; its
        // second sleep only happens after the skipped refresh returns
        // through the in-flight guard.
        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "replacement loop parked past the in-flight run") {
            (sleep.callCount >= 2) ? true : nil
        }
        #expect(runner.callCount == 1)

        runner.open()
        sleep.release()
        _ = try await eventually(description: "gated token stored") {
            (try? store.read(providerID: providerID)) == "gated" ? true : nil
        }
        sleep.release()
        await refresher.cancelAll()
    }

    @Test("A stale run outliving its rescheduled loop never writes the token")
    func staleRunDoesNotOverwriteFreshToken() async throws {
        let store = MemorySecretStore()
        let runner = GatedRunner()
        let sleep = FirstThenHeldSleep()
        let refresher = makeRefresher(store: store, runner: runner) { seconds in
            try await sleep.sleep(seconds: seconds)
        }
        let providerID = UUID()
        // The token a concurrent save flow just wrote before rescheduling.
        try store.write("fresh-token", providerID: providerID)

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "stale run entered") {
            (runner.callCount == 1) ? true : nil
        }

        // The save flow's reschedule: the old task is cancelled and the
        // tombstone removed while the old run is still parked in the runner.
        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: false,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "replacement loop parked") {
            (sleep.callCount >= 2) ? true : nil
        }

        runner.open()
        try await Task.sleep(for: .milliseconds(300))
        // The just-saved token stands; the stale run must not clobber it
        // for a full refresh interval.
        #expect(try store.read(providerID: providerID) == "fresh-token")
        sleep.release()
        await refresher.cancelAll()
    }

    @Test("A run cancelled in flight bows out without recording a failure")
    func cancelledRunRecordsNoFailure() async throws {
        let store = MemorySecretStore()
        let runner = CancellingRunner()
        let refresher = makeRefresher(store: store, runner: runner)
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "run entered") {
            (runner.callCount == 1) ? true : nil
        }

        await refresher.cancel(providerID: providerID)
        _ = try await eventually(description: "in-flight run bowed out") {
            runner.threwCancellation ? true : nil
        }
        #expect(await refresher.failureMessages().isEmpty)
        #expect(try store.read(providerID: providerID) == nil)
    }

    @Test("A late non-cancellation failure from a torn-down run stays silent")
    func lateFailureStaysSilentAfterTeardown() async throws {
        let store = MemorySecretStore()
        let runner = LateFailingRunner()
        let refresher = makeRefresher(store: store, runner: runner)
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "run entered") {
            (runner.callCount == 1) ? true : nil
        }

        await refresher.cancel(providerID: providerID)
        runner.open()
        try await Task.sleep(for: .milliseconds(300))
        // A failure that lands after teardown must not resurrect an outcome
        // for a provider whose loop is gone — its badge would persist until
        // the next save.
        #expect(await refresher.failureMessages().isEmpty)
    }

    @Test("A cancelled in-flight run does not overwrite the stored credential")
    func cancelledRunLeavesStoreUntouched() async throws {
        let store = MemorySecretStore()
        let runner = GatedRunner()
        let refresher = makeRefresher(store: store, runner: runner)
        let providerID = UUID()

        await refresher.schedule(
            providerID: providerID,
            interval: 3_600,
            immediate: true,
            scriptPath: "echo token"
        )
        _ = try await eventually(description: "gated run entered") {
            (runner.callCount == 1) ? true : nil
        }

        await refresher.cancel(providerID: providerID)
        runner.open()
        try await Task.sleep(for: .milliseconds(150))
        #expect(try store.read(providerID: providerID) == nil)
        #expect(await refresher.failureMessages().isEmpty)
    }
}
