import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway state admission races")
struct GatewayStateRaceTests {
    @Test("Stopping while an admission awaits reconfiguration rejects it after the await")
    func stopDuringReconfiguration() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let pool = ControlledGatewayRequestPool(blockFirstReconfiguration: true)
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let replacement = Task {
            await state.replace(
                providers: fixture.snapshot.providers,
                mappings: fixture.snapshot.mappings
            )
        }
        try await waitForGatewayRequestPool(pool) { await $0.reconfigurationCallCount == 1 }

        let admissionWaitingForReconfiguration = AsyncTestGate()
        let admission = Task {
            try await state.admit(
                gatewayStateRaceAdmission(
                    capture: await state.routingCapture(),
                    provider: provider
                )
            ) {
                await admissionWaitingForReconfiguration.open()
            }
        }
        try await admissionWaitingForReconfiguration.wait(
            description: "the admission to await reconfiguration"
        )
        let stopping = Task { await state.stopAdmissions() }
        let _: Bool = try await eventually(
            description: "the gateway state to stop accepting requests"
        ) {
            do {
                try await state.admit(client: .claude)
                return nil
            } catch GatewayState.Error.notAcceptingRequests {
                return true
            }
        }
        await pool.releaseReconfiguration()

        _ = await replacement.value
        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await admission.value
        }
        await stopping.value
        #expect(await pool.shutdownCallCount == 1)
    }

    @Test("A pool shutdown race is translated to the public gateway state error")
    func poolShutdownRace() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let pool = ControlledGatewayRequestPool(admissionError: .notAcceptingRequests)
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)

        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await state.admit(
                gatewayStateRaceAdmission(
                    capture: await state.routingCapture(),
                    provider: provider
                )
            )
        }
    }

    @Test("Stopping after the pool grants an admission releases and rejects it")
    func stopAfterPoolGrant() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let pool = ControlledGatewayRequestPool(blockFirstAdmission: true)
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let eventID = UUID()
        let admission = Task {
            try await state.admit(
                gatewayStateRaceAdmission(
                    eventID: eventID,
                    capture: await state.routingCapture(),
                    provider: provider
                )
            )
        }
        try await waitForGatewayRequestPool(pool) { await $0.admissionCallCount == 1 }

        let stopping = Task { await state.stopAdmissions() }
        try await waitForGatewayRequestPool(pool) { await $0.shutdownCallCount == 1 }
        await pool.releaseAdmission()

        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await admission.value
        }
        await stopping.value
        #expect(await pool.finishedEventIDs == [eventID])
        #expect(await state.sessionRequestCount == 0)
    }

    @Test("An image probe invalidated after its pool grant releases the permit", arguments: [false, true])
    func imageProbeInvalidationAfterPoolGrant(stopping: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let model = try #require(provider.models.first)
        let pool = ControlledGatewayRequestPool(blockFirstAdmission: true)
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let eventID = UUID()
        let admission = Task {
            try await state.admitImageProbe(eventID: eventID, provider: provider, modelID: model.id)
        }
        try await waitForGatewayRequestPool(pool) { await $0.admissionCallCount == 1 }

        if stopping {
            await state.stopAdmissions()
        } else {
            await state.replace(
                providers: fixture.snapshot.providers,
                mappings: fixture.snapshot.mappings,
                credentialChangedProviderIDs: [provider.id])
        }
        await pool.releaseAdmission()

        await #expect(throws: GatewayAdmissionError.invalidated) { try await admission.value }
        #expect(await pool.finishedEventIDs == [eventID])
        #expect(await state.sessionRequestCount == 0)
    }

    @Test("A capture without a provider revision is invalidated before reaching the pool")
    func missingProviderRevision() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let pool = ControlledGatewayRequestPool()
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let capture = GatewayRoutingCapture(
            snapshot: fixture.snapshot,
            providerRevisions: [:]
        )

        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await state.admit(
                gatewayStateRaceAdmission(capture: capture, provider: provider)
            )
        }
        #expect(await pool.admissionCallCount == 0)
    }

    @Test("A snapshot retries when routing changes while the pool snapshot is suspended")
    func snapshotGenerationRetry() async throws {
        let fixture = try GatewayTests().makeFixture()
        let pool = ControlledGatewayRequestPool(blockFirstSnapshot: true)
        let state = GatewayState(snapshot: fixture.snapshot, requestPool: pool)
        let snapshotTask = Task { await state.requestPoolSnapshot() }
        try await waitForGatewayRequestPool(pool) { await $0.snapshotCallCount == 1 }

        _ = await state.replace(
            providers: fixture.snapshot.providers,
            mappings: fixture.snapshot.mappings
        )
        await pool.releaseSnapshot()

        _ = await snapshotTask.value
        #expect(await pool.snapshotCallCount == 2)
    }

    @Test("Removing and re-adding the same provider advances its revision")
    func providerReadditionRevision() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let state = GatewayState(snapshot: fixture.snapshot)

        _ = await state.replace(providers: [], mappings: [:])
        _ = await state.replace(
            providers: [provider],
            mappings: fixture.snapshot.mappings
        )

        #expect(await state.routingCapture().providerRevision(for: provider.id) == 2)
    }

    @Test("A missing revision defaults to zero in a pool configuration")
    func missingPoolConfigurationRevision() throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)

        let configuration = fixture.snapshot.providerRequestPoolConfiguration(
            providerRevisions: [:]
        )

        #expect(configuration.providers.first?.id == provider.id)
        #expect(configuration.providers.first?.revision == 0)
    }
}

private func gatewayStateRaceAdmission(
    eventID: UUID = UUID(),
    capture: GatewayRoutingCapture,
    provider: Provider
) -> GatewayRequestAdmission {
    GatewayRequestAdmission(
        eventID: eventID,
        capture: capture,
        client: .claude,
        modelIdentifier: "claude-opus-5",
        providerID: provider.id,
        targetModelID: "glm-5.2",
        retainedBodyBytes: 1
    )
}

private actor ControlledGatewayRequestPool: ProviderRequestPooling {
    private let admissionError: GatewayAdmissionError?
    private let blockFirstAdmission: Bool
    private let blockFirstReconfiguration: Bool
    private let blockFirstSnapshot: Bool
    private let admissionReleased = AsyncTestGate()
    private let reconfigurationReleased = AsyncTestGate()
    private let snapshotReleased = AsyncTestGate()

    private(set) var admissionCallCount = 0
    private(set) var reconfigurationCallCount = 0
    private(set) var snapshotCallCount = 0
    private(set) var shutdownCallCount = 0
    private(set) var finishedEventIDs: [UUID] = []

    init(
        admissionError: GatewayAdmissionError? = nil,
        blockFirstAdmission: Bool = false,
        blockFirstReconfiguration: Bool = false,
        blockFirstSnapshot: Bool = false
    ) {
        self.admissionError = admissionError
        self.blockFirstAdmission = blockFirstAdmission
        self.blockFirstReconfiguration = blockFirstReconfiguration
        self.blockFirstSnapshot = blockFirstSnapshot
    }

    func admit(_ admission: ProviderRequestAdmission) async throws {
        _ = admission
        admissionCallCount += 1
        if blockFirstAdmission, admissionCallCount == 1 {
            try await admissionReleased.wait()
        }
        if let admissionError {
            throw admissionError
        }
    }

    func finish(eventID: UUID) async {
        finishedEventIDs.append(eventID)
    }

    func shutdown() async {
        shutdownCallCount += 1
    }

    func reconfigure(_ configuration: ProviderRequestPoolConfiguration) async {
        _ = configuration
        reconfigurationCallCount += 1
        guard blockFirstReconfiguration, reconfigurationCallCount == 1 else { return }
        try? await reconfigurationReleased.wait()
    }

    func snapshot() async -> ProviderRequestPoolSnapshot {
        snapshotCallCount += 1
        if blockFirstSnapshot, snapshotCallCount == 1 {
            try? await snapshotReleased.wait()
        }
        return ProviderRequestPoolSnapshot(
            totalRunning: 0,
            totalWaiting: 0,
            providers: []
        )
    }

    func releaseReconfiguration() async {
        await reconfigurationReleased.open()
    }

    func releaseAdmission() async {
        await admissionReleased.open()
    }

    func releaseSnapshot() async {
        await snapshotReleased.open()
    }
}

private func waitForGatewayRequestPool(
    _ pool: ControlledGatewayRequestPool,
    condition: @escaping @Sendable (ControlledGatewayRequestPool) async -> Bool
) async throws {
    let _: Bool = try await eventually(
        description: "the controlled gateway request pool condition"
    ) {
        await condition(pool) ? true : nil
    }
}
