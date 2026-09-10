import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider request pool state machine")
struct ProviderRequestPoolStateMachineTests {
    @Test("Fixed-seed mixed transitions preserve all observable invariants")
    func fixedSeedStateMachine() async throws {
        let timing = ManualProviderRequestPoolTiming()
        var state = MachineState(reference: machineInitialReference(), timing: timing)
        let pool = ProviderRequestPool(
            configuration: machineConfiguration(state.reference),
            timing: timing
        )
        var generator = ProviderRequestPoolGenerator(seed: 0xA11C_E5ED_F1F0_2026)
        var operationCounts = Array(repeating: 0, count: 8)

        try await seedMachine(pool: pool, state: &state)
        await assertMachineInvariants(pool: pool, state: state)

        for _ in 0..<256 {
            let operation = Int(generator.next() % 8)
            let providerID = machineProviderOrder[
                Int(generator.next() % UInt64(machineProviderOrder.count))
            ]
            let performed = try await performMachineOperation(
                operation,
                providerID: providerID,
                pool: pool,
                state: &state,
                generator: &generator
            )
            if performed {
                operationCounts[operation] += 1
                await assertMachineInvariants(pool: pool, state: state)
            }
        }

        for (operation, count) in operationCounts.enumerated() {
            #expect(count > 0, "State-machine operation \(operation) did not execute")
        }
        await shutdownMachine(pool: pool, state: &state)
    }
}

private func machineInitialReference() -> [UUID: MachineProvider] {
    let alpha = MachineProvider(
        id: ProviderRequestPoolTestIDs.alpha,
        displayName: "Alpha",
        limit: 1,
        revision: 0,
        modelIdentifier: "claude-alpha",
        baseTargetModelID: "alpha-model",
        targetModelID: "alpha-model",
        isConfigured: true
    )
    let beta = MachineProvider(
        id: ProviderRequestPoolTestIDs.beta,
        displayName: "Beta",
        limit: 1,
        revision: 0,
        modelIdentifier: "claude-beta",
        baseTargetModelID: "beta-model",
        targetModelID: "beta-model",
        isConfigured: true
    )
    return [alpha.id: alpha, beta.id: beta]
}

private func machineConfiguration(
    _ reference: [UUID: MachineProvider]
) -> ProviderRequestPoolConfiguration {
    var routes: [ProviderRequestRouteKey: ProviderRequestRouteTarget] = [:]
    let providers = machineProviderOrder.compactMap { id -> ProviderRequestPoolProviderConfiguration? in
        guard let provider = reference[id], provider.isConfigured else {
            return nil
        }
        routes[
            ProviderRequestRouteKey(
                client: .claude,
                modelIdentifier: provider.modelIdentifier
            )] = ProviderRequestRouteTarget(
                providerID: id,
                modelID: provider.targetModelID
            )
        return ProviderRequestPoolProviderConfiguration(
            id: id,
            displayName: provider.displayName,
            maximumParallelRequests: provider.limit,
            revision: provider.revision
        )
    }
    return ProviderRequestPoolConfiguration(providers: providers, routes: routes)
}

private func machineAdmission(
    for provider: MachineProvider,
    retainedBodyBytes: Int
) -> ProviderRequestAdmission {
    providerRequestAdmission(
        providerID: provider.id,
        providerRevision: provider.revision,
        modelIdentifier: provider.modelIdentifier,
        targetModelID: provider.targetModelID,
        retainedBodyBytes: retainedBodyBytes
    )
}

private func machineWaitingCount(_ reference: [UUID: MachineProvider]) -> Int {
    reference.values.reduce(0) { $0 + $1.waiting.count }
}

private func seedMachine(
    pool: ProviderRequestPool,
    state: inout MachineState
) async throws {
    for providerID in machineProviderOrder {
        guard var provider = state.reference[providerID] else {
            Issue.record("Missing seeded provider \(providerID)")
            continue
        }
        let active = machineAdmission(for: provider, retainedBodyBytes: 3)
        try await pool.admit(active)
        provider.active[active.eventID] = active
        state.reference[providerID] = provider
        for charge in [5, 7] {
            let admission = machineAdmission(for: provider, retainedBodyBytes: charge)
            let task = providerRequestAdmissionTask(pool: pool, admission: admission)
            provider.waiting.append(MachineWaiter(admission: admission, task: task))
            state.reference[providerID] = provider
            let expectedWaiting = machineWaitingCount(state.reference)
            _ = try await waitForProviderRequestPoolSnapshot(pool) {
                $0.totalWaiting == expectedWaiting
            }
        }
    }
}

private func performMachineOperation(
    _ operation: Int,
    providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState,
    generator: inout ProviderRequestPoolGenerator
) async throws -> Bool {
    switch operation {
    case 0:
        return try await machineAddRequest(
            providerID,
            pool: pool,
            state: &state,
            generator: &generator
        )
    case 1:
        return await machineFinishRequest(providerID, pool: pool, state: &state)
    case 2:
        return await machineCancelWaiter(providerID, state: &state, generator: &generator)
    case 3:
        return await machineResizeProvider(
            providerID,
            pool: pool,
            state: &state,
            generator: &generator
        )
    case 4:
        return await machineChangeRevision(providerID, pool: pool, state: &state)
    case 5:
        return await machineChangeRoute(providerID, pool: pool, state: &state)
    case 6:
        return await machineToggleProvider(providerID, pool: pool, state: &state)
    case 7:
        let timing = state.timing
        return await machineTimeoutWaiters(timing: timing, state: &state)
    default:
        return false
    }
}

private func machineAddRequest(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState,
    generator: inout ProviderRequestPoolGenerator
) async throws -> Bool {
    guard var provider = state.reference[providerID], provider.isConfigured,
        provider.active.count + provider.waiting.count < 12
    else {
        return false
    }
    let admission = machineAdmission(
        for: provider,
        retainedBodyBytes: Int(generator.next() % 31) + 1
    )
    if provider.active.count < provider.limit, provider.waiting.isEmpty {
        try await pool.admit(admission)
        provider.active[admission.eventID] = admission
    } else {
        let task = providerRequestAdmissionTask(pool: pool, admission: admission)
        provider.waiting.append(MachineWaiter(admission: admission, task: task))
        state.reference[providerID] = provider
        let expectedWaiting = machineWaitingCount(state.reference)
        _ = try await waitForProviderRequestPoolSnapshot(pool) {
            $0.totalWaiting == expectedWaiting
        }
    }
    state.reference[providerID] = provider
    return true
}

private func machineFinishRequest(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState
) async -> Bool {
    guard var provider = state.reference[providerID],
        let eventID = provider.active.keys.min(by: { $0.uuidString < $1.uuidString })
    else {
        return false
    }
    await pool.finish(eventID: eventID)
    provider.active[eventID] = nil
    if provider.isConfigured {
        await machinePromoteWaiters(&provider)
    } else if provider.active.isEmpty {
        state.removedOrder.removeAll { $0 == providerID }
    }
    state.reference[providerID] = provider
    return true
}

private func machineCancelWaiter(
    _ providerID: UUID,
    state: inout MachineState,
    generator: inout ProviderRequestPoolGenerator
) async -> Bool {
    guard var provider = state.reference[providerID], !provider.waiting.isEmpty else {
        return false
    }
    let index = Int(generator.next() % UInt64(provider.waiting.count))
    let waiter = provider.waiting.remove(at: index)
    waiter.task.cancel()
    #expect(await waiter.task.value == .cancelled)
    state.reference[providerID] = provider
    return true
}

private func machineResizeProvider(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState,
    generator: inout ProviderRequestPoolGenerator
) async -> Bool {
    guard var provider = state.reference[providerID], provider.isConfigured else {
        return false
    }
    provider.limit = Int(generator.next() % 4) + 1
    state.reference[providerID] = provider
    await pool.reconfigure(machineConfiguration(state.reference))
    await machinePromoteWaiters(&provider)
    state.reference[providerID] = provider
    return true
}

private func machineChangeRevision(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState
) async -> Bool {
    guard var provider = state.reference[providerID], provider.isConfigured else {
        return false
    }
    provider.revision &+= 1
    let invalidated = provider.waiting
    provider.waiting = []
    state.reference[providerID] = provider
    await pool.reconfigure(machineConfiguration(state.reference))
    await expectInvalidated(invalidated)
    return true
}

private func machineChangeRoute(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState
) async -> Bool {
    guard var provider = state.reference[providerID], provider.isConfigured else {
        return false
    }
    provider.targetModelID =
        provider.targetModelID.hasSuffix("-replacement")
        ? provider.baseTargetModelID
        : provider.baseTargetModelID + "-replacement"
    let invalidated = provider.waiting
    provider.waiting = []
    state.reference[providerID] = provider
    await pool.reconfigure(machineConfiguration(state.reference))
    await expectInvalidated(invalidated)
    return true
}

private func machineToggleProvider(
    _ providerID: UUID,
    pool: ProviderRequestPool,
    state: inout MachineState
) async -> Bool {
    guard var provider = state.reference[providerID] else {
        Issue.record("Missing toggled provider \(providerID)")
        return false
    }
    if provider.isConfigured {
        provider.isConfigured = false
        let invalidated = provider.waiting
        provider.waiting = []
        if !provider.active.isEmpty, !state.removedOrder.contains(providerID) {
            state.removedOrder.append(providerID)
        }
        state.reference[providerID] = provider
        await pool.reconfigure(machineConfiguration(state.reference))
        await expectInvalidated(invalidated)
    } else {
        provider.isConfigured = true
        provider.revision &+= 1
        provider.displayName += " restored"
        state.removedOrder.removeAll { $0 == providerID }
        state.reference[providerID] = provider
        await pool.reconfigure(machineConfiguration(state.reference))
    }
    return true
}

private func machineTimeoutWaiters(
    timing: ManualProviderRequestPoolTiming,
    state: inout MachineState
) async -> Bool {
    let timedOut = state.reference.values.flatMap(\.waiting)
    guard !timedOut.isEmpty else {
        return false
    }
    await timing.advance(by: ProviderRequestPool.waitTimeout)
    for waiter in timedOut {
        #expect(await waiter.task.value == .failed(.timedOut))
    }
    for providerID in machineProviderOrder {
        guard var provider = state.reference[providerID] else {
            continue
        }
        provider.waiting = []
        state.reference[providerID] = provider
    }
    return true
}

private func machinePromoteWaiters(_ provider: inout MachineProvider) async {
    while provider.active.count < provider.limit, !provider.waiting.isEmpty {
        let waiter = provider.waiting.removeFirst()
        #expect(await waiter.task.value == .admitted)
        provider.active[waiter.admission.eventID] = waiter.admission
    }
}

private func expectInvalidated(_ waiters: [MachineWaiter]) async {
    for waiter in waiters {
        #expect(await waiter.task.value == .failed(.invalidated))
    }
}

private func shutdownMachine(
    pool: ProviderRequestPool,
    state: inout MachineState
) async {
    let stoppedWaiters = state.reference.values.flatMap(\.waiting)
    await pool.shutdown()
    for waiter in stoppedWaiters {
        #expect(await waiter.task.value == .failed(.notAcceptingRequests))
    }
    for providerID in machineProviderOrder {
        guard var provider = state.reference[providerID] else {
            continue
        }
        provider.waiting = []
        state.reference[providerID] = provider
    }
    if let provider = state.reference.values.first {
        await #expect(throws: GatewayAdmissionError.notAcceptingRequests) {
            try await pool.admit(machineAdmission(for: provider, retainedBodyBytes: 1))
        }
    } else {
        Issue.record("Missing provider for shutdown admission")
    }
    for providerID in machineProviderOrder {
        guard var provider = state.reference[providerID] else {
            continue
        }
        for eventID in Array(provider.active.keys) {
            await pool.finish(eventID: eventID)
            provider.active[eventID] = nil
        }
        state.reference[providerID] = provider
    }
    state.removedOrder = []
    await assertMachineInvariants(pool: pool, state: state)
}

private func assertMachineInvariants(
    pool: ProviderRequestPool,
    state: MachineState
) async {
    let snapshot = await pool.snapshot()
    let configuredIDs = machineProviderOrder.filter {
        state.reference[$0]?.isConfigured == true
    }
    let drainingIDs = state.removedOrder.filter {
        state.reference[$0]?.isConfigured == false
            && state.reference[$0]?.active.isEmpty == false
    }
    #expect(snapshot.providers.map(\.id) == configuredIDs + drainingIDs)
    #expect(
        snapshot.totalRunning
            == snapshot.providers.reduce(0) {
                $0 + $1.runningCount
            })
    #expect(
        snapshot.totalWaiting
            == snapshot.providers.reduce(0) {
                $0 + $1.waitingCount
            })
    #expect(
        snapshot.totalRunning
            == state.reference.values.reduce(0) {
                $0 + $1.active.count
            })
    #expect(snapshot.totalWaiting == machineWaitingCount(state.reference))
    #expect(Set(snapshot.providers.map(\.id)).count == snapshot.providers.count)

    for providerSnapshot in snapshot.providers {
        guard let provider = state.reference[providerSnapshot.id] else {
            Issue.record("Missing snapshotted provider \(providerSnapshot.id)")
            continue
        }
        #expect(providerSnapshot.runningCount == provider.active.count)
        #expect(providerSnapshot.waitingCount == provider.waiting.count)
        #expect(
            providerSnapshot.retainedWaitingBytes
                == provider.waiting.reduce(0) {
                    $0 + $1.admission.retainedBodyBytes
                })
        #expect(providerSnapshot.maximumParallelRequests == provider.limit)
        #expect(providerSnapshot.isRemoved == !provider.isConfigured)
        #expect(providerSnapshot.displayName == provider.displayName)
        #expect((providerSnapshot.oldestWaitDuration == nil) == provider.waiting.isEmpty)
        #expect(providerSnapshot.waitingCount <= ProviderRequestPool.maximumWaitingRequests)
        #expect(
            providerSnapshot.retainedWaitingBytes
                <= ProviderRequestPool.maximumRetainedWaitingBytes
        )
    }
}
