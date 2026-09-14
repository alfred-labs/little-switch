import Foundation
import LittleSwitchCommon

/// The pause a refresh loop takes between runs. Injectable so tests can gate
/// the cadence instead of waiting real intervals.
public typealias CredentialRefresherSleep = @Sendable (TimeInterval) async throws -> Void

/// Runs credential scripts on a per-provider schedule, storing each produced
/// token in the keychain so the gateway keeps serving the last valid token
/// while the next refresh runs. Each (re)schedule carries the script path.
public actor CredentialRefresher {
    private struct Schedule {
        let interval: TimeInterval
        let immediate: Bool
        let scriptPath: String
    }

    private let secretStore: any SecretStore
    private let runner: any CredentialScriptRunning
    private let sleep: CredentialRefresherSleep
    private var schedules: [UUID: Schedule] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var running: Set<UUID> = []
    /// Providers torn down by `cancel(_:)` or `cancelAll()`; their late
    /// in-flight runs stay silent. Rescheduling reopens a provider.
    private var terminatedProviders: Set<UUID> = []
    private var outcomes: [UUID: CredentialRefreshOutcome] = [:]

    public init(
        secretStore: any SecretStore,
        runner: any CredentialScriptRunning,
        sleep: @escaping CredentialRefresherSleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.secretStore = secretStore
        self.runner = runner
        self.sleep = sleep
    }

    /// (Re)starts the refresh loop for a provider. A previous loop is
    /// cancelled; an in-flight run finishes before the new cadence applies.
    public func schedule(
        providerID: UUID,
        interval: TimeInterval,
        immediate: Bool,
        scriptPath: String
    ) {
        tasks[providerID]?.cancel()
        terminatedProviders.remove(providerID)
        let schedule = Schedule(
            interval: max(60, interval),
            immediate: immediate,
            scriptPath: scriptPath
        )
        schedules[providerID] = schedule
        tasks[providerID] = Task { [weak self] in
            await self?.loop(providerID: providerID, schedule: schedule)
        }
    }

    public func cancel(providerID: UUID) {
        tasks[providerID]?.cancel()
        tasks[providerID] = nil
        schedules[providerID] = nil
        outcomes[providerID] = nil
        terminatedProviders.insert(providerID)
    }

    public func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        terminatedProviders.formUnion(tasks.keys)
        tasks.removeAll()
        schedules.removeAll()
        outcomes.removeAll()
    }

    public func failureMessages() -> [UUID: String] {
        outcomes.compactMapValues { outcome in
            outcome.kind == .failed ? outcome.message : nil
        }
    }

    /// The stderr tail of every provider's last run, successes included: the
    /// editor shows what the script last said, not only why it failed.
    public func lastScriptOutputs() -> [UUID: String] {
        outcomes.compactMapValues { outcome in
            outcome.standardError.isEmpty ? nil : outcome.standardError
        }
    }

    private func loop(providerID: UUID, schedule: Schedule) async {
        var first = schedule.immediate
        while !Task.isCancelled {
            if !first {
                do {
                    try await sleep(schedule.interval)
                } catch {
                    break
                }
            }
            first = false
            await refresh(providerID: providerID, schedule: schedule)
        }
    }

    private func refresh(providerID: UUID, schedule: Schedule) async {
        guard !running.contains(providerID) else {
            return
        }
        running.insert(providerID)
        defer { running.remove(providerID) }
        do {
            let run = try await produceToken(scriptPath: schedule.scriptPath)
            // Task.isCancelled catches the run whose loop was cancelled and
            // rescheduled under it: the tombstone is gone by then, and its
            // late token must not clobber the one the save flow just wrote.
            if terminatedProviders.contains(providerID) || Task.isCancelled { return }
            try secretStore.write(run.token, providerID: providerID)
            record(
                providerID: providerID,
                outcome: CredentialRefreshOutcome(
                    kind: .refreshed,
                    standardError: run.standardError
                )
            )
        } catch is CancellationError {
            return
        } catch {
            // Only a live loop's failures surface: a run torn down under a
            // cancel must neither write the keychain (guarded above) nor
            // resurrect an outcome the teardown already cleared.
            guard !terminatedProviders.contains(providerID), !Task.isCancelled else {
                return
            }
            record(providerID: providerID, outcome: .failure(from: error))
        }
    }

    private func produceToken(scriptPath scheduledPath: String) async throws -> CredentialScriptRun {
        let scriptPath = scheduledPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scriptPath.isEmpty else {
            throw CredentialScriptError(reason: .missingScriptPath, standardError: "")
        }
        return try await runner.run(scriptPath: scriptPath)
    }

    package func record(providerID: UUID, outcome: CredentialRefreshOutcome) {
        outcomes[providerID] = outcome
    }
}
