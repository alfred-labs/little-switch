import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Gateway state counts only granted pool admissions and finishes idempotently")
    func pooledGatewayStateAdmission() async throws {
        let fixture = try makeFixture()
        var provider = try #require(fixture.snapshot.providers.first)
        provider.maximumParallelRequests = 1
        let snapshot = RoutingSnapshot(
            generation: fixture.snapshot.generation,
            providers: [provider],
            mappings: fixture.snapshot.mappings,
            codex: fixture.snapshot.codex
        )
        let state = GatewayState(snapshot: snapshot)
        let capture = await state.routingCapture()
        let firstEventID = UUID()
        let secondEventID = UUID()

        try await state.admit(
            GatewayRequestAdmission(
                eventID: firstEventID,
                capture: capture,
                client: .claude,
                modelIdentifier: "claude-opus-5",
                providerID: provider.id,
                targetModelID: "glm-5.2",
                retainedBodyBytes: 7
            )
        )
        let second = Task {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: secondEventID,
                    capture: capture,
                    client: .codex,
                    modelIdentifier: CodexCatalog.slug(
                        for: CodexModelTarget(
                            provider: provider,
                            model: DiscoveredModel(id: "glm-5.2")
                        )
                    ),
                    providerID: provider.id,
                    targetModelID: "glm-5.2",
                    retainedBodyBytes: 11
                )
            )
        }
        _ = try await waitForGatewayPoolSnapshot(state) { $0.totalWaiting == 1 }

        #expect(await state.sessionRequestCount == 1)
        #expect(await state.claudeSessionRequestCount == 1)
        #expect(await state.codexSessionRequestCount == 0)
        await state.finish(eventID: firstEventID)
        try await second.value
        #expect(await state.sessionRequestCount == 2)
        #expect(await state.codexSessionRequestCount == 1)
        await state.finish(eventID: secondEventID)
        await state.finish(eventID: secondEventID)
        #expect((await state.requestPoolSnapshot()).totalRunning == 0)
    }

    @Test("Routing captures cover Claude and Codex while selective changes invalidate stale work")
    func routingCaptureRevisions() async throws {
        let fixture = try makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let state = GatewayState(snapshot: fixture.snapshot)
        let original = await state.routingCapture()
        let originalRevision = try #require(original.providerRevision(for: provider.id))

        var resized = provider
        resized.maximumParallelRequests = 2
        let resizedSnapshot = await state.replace(
            providers: [resized],
            mappings: fixture.snapshot.mappings,
            codex: fixture.snapshot.codex
        )
        #expect(resizedSnapshot.generation == fixture.snapshot.generation + 1)
        #expect(await state.routingCapture().providerRevision(for: provider.id) == originalRevision)
        let activeEventID = UUID()
        try await state.admit(
            GatewayRequestAdmission(
                eventID: activeEventID,
                capture: original,
                client: .claude,
                modelIdentifier: "claude-opus-5",
                providerID: provider.id,
                targetModelID: "glm-5.2",
                retainedBodyBytes: 1
            )
        )

        var endpointChanged = resized
        endpointChanged.baseURL += "/changed"
        _ = await state.replace(
            providers: [endpointChanged],
            mappings: fixture.snapshot.mappings,
            codex: fixture.snapshot.codex
        )
        #expect(
            await state.routingCapture().providerRevision(for: provider.id)
                == originalRevision + 1
        )
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: UUID(),
                    capture: original,
                    client: .claude,
                    modelIdentifier: "claude-opus-5",
                    providerID: provider.id,
                    targetModelID: "glm-5.2",
                    retainedBodyBytes: 1
                )
            )
        }
        #expect(original.snapshot.providers.first?.baseURL == provider.baseURL)
        #expect((await state.requestPoolSnapshot()).totalRunning == 1)
        await state.finish(eventID: activeEventID)

        let credentialCapture = await state.routingCapture()
        _ = await state.replace(
            providers: [endpointChanged],
            mappings: fixture.snapshot.mappings,
            codex: fixture.snapshot.codex,
            credentialChangedProviderIDs: [provider.id]
        )
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: UUID(),
                    capture: credentialCapture,
                    client: .claude,
                    modelIdentifier: "claude-opus-5",
                    providerID: provider.id,
                    targetModelID: "glm-5.2",
                    retainedBodyBytes: 1
                )
            )
        }
    }

    @Test("Overlapping replacements preserve every provider revision")
    func overlappingRoutingReplacementsAreSerialized() async throws {
        let fixture = try makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        let state = GatewayState(snapshot: fixture.snapshot)
        let replacementCount = 64

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<replacementCount {
                group.addTask {
                    var replacement = provider
                    replacement.baseURL += "/replacement-\(index)"
                    _ = await state.replace(
                        providers: [replacement],
                        mappings: fixture.snapshot.mappings,
                        codex: fixture.snapshot.codex
                    )
                }
            }
        }

        let capture = await state.routingCapture()
        #expect(capture.providerRevision(for: provider.id) == UInt64(replacementCount))
        #expect(capture.snapshot.generation == fixture.snapshot.generation + UInt64(replacementCount))
    }

    @Test("Changed routes invalidate queued captures, and stopping closes the pool")
    func routeInvalidationAndShutdown() async throws {
        let fixture = try makeFixture()
        var configuredProvider = try #require(fixture.snapshot.providers.first)
        configuredProvider.maximumParallelRequests = 1
        configuredProvider.models.append(DiscoveredModel(id: "replacement"))
        let provider = configuredProvider
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: fixture.snapshot.generation,
                providers: [provider],
                mappings: fixture.snapshot.mappings,
                codex: fixture.snapshot.codex
            )
        )
        let capture = await state.routingCapture()
        let activeEventID = UUID()
        try await state.admit(
            GatewayRequestAdmission(
                eventID: activeEventID,
                capture: capture,
                client: .claude,
                modelIdentifier: "claude-opus-5",
                providerID: provider.id,
                targetModelID: "glm-5.2",
                retainedBodyBytes: 1
            )
        )
        let waiting = Task {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: UUID(),
                    capture: capture,
                    client: .claude,
                    modelIdentifier: "claude-opus-5",
                    providerID: provider.id,
                    targetModelID: "glm-5.2",
                    retainedBodyBytes: 1
                )
            )
        }
        _ = try await waitForGatewayPoolSnapshot(state) { $0.totalWaiting == 1 }

        _ = await state.replace(
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(
                    providerID: provider.id,
                    modelID: "replacement"
                )
            ],
            codex: fixture.snapshot.codex
        )
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await waiting.value
        }
        #expect(await state.sessionRequestCount == 1)
        await state.stopAdmissions()
        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await state.admit(
                GatewayRequestAdmission(
                    eventID: UUID(),
                    capture: await state.routingCapture(),
                    client: .claude,
                    modelIdentifier: "claude-opus-5",
                    providerID: provider.id,
                    targetModelID: "replacement",
                    retainedBodyBytes: 1
                )
            )
        }
        await state.finish(eventID: activeEventID)
        #expect((await state.requestPoolSnapshot()).totalRunning == 0)
    }

    @Test("Gateway state preserves captured routing and rejects stopped admissions")
    func gatewayStateAdmissions() async throws {
        let fixture = try makeFixture()
        let state = GatewayState(snapshot: fixture.snapshot)

        let admitted = await state.capture()
        let currentProvider = try #require(fixture.snapshot.providers.first)
        let replacementProvider = Provider(
            id: currentProvider.id,
            name: currentProvider.name,
            baseURL: currentProvider.baseURL,
            authMode: currentProvider.authMode,
            models: [DiscoveredModel(id: "replacement")]
        )
        let replacement = await state.replace(
            providers: [replacementProvider],
            mappings: [
                "claude-opus-5": ModelMapping(
                    providerID: replacementProvider.id,
                    modelID: "replacement"
                )
            ]
        )

        try await state.admit(client: .claude)
        try await state.admit(client: .codex)
        #expect(await state.claudeSessionRequestCount == 1)
        #expect(await state.codexSessionRequestCount == 1)
        #expect(await state.sessionRequestCount == 2)
        #expect(replacement.generation == fixture.snapshot.generation + 1)
        #expect(admitted.resolve(model: "claude-opus-5")?.modelID == "glm-5.2")
        #expect(replacement.resolve(model: "claude-opus-5")?.modelID == "replacement")

        await state.stopAdmissions()
        await #expect(throws: GatewayState.Error.notAcceptingRequests) {
            try await state.admit()
        }
        #expect(await state.sessionRequestCount == 2)
    }

    @Test("Unexpected admission failures return safe client-specific errors")
    func unexpectedAdmissionFailure() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            dependencies: GatewayResponderDependencies(
                admitter: ThrowingGatewayAdmitter()
            )
        )
        let app = Application(responder: responder)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(messages.status == .internalServerError)
            let messageBody = String(buffer: messages.body)
            #expect(messageBody.contains("Could not admit request"))
            #expect(!messageBody.contains("private-admission"))

            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(responses.status == .internalServerError)
            let responsesBody = String(buffer: responses.body)
            #expect(responsesBody.contains("Could not admit request"))
            #expect(!responsesBody.contains("private-admission"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Admission cancellation propagates for direct and web-search requests")
    func admissionCancellation() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let recorder = TrafficTestRecorder()
        let transport = RecordingGatewayTransport(responses: [])
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder,
                dependencies: GatewayResponderDependencies(
                    admitter: CancellingGatewayAdmitter()
                )
            )
        )
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            for (path, body) in [
                ("/v1/messages", #"{"model":"claude-opus-5","messages":[]}"#),
                (
                    "/v1/messages",
                    #"{"model":"claude-opus-5","messages":[],"tools":[{"type":"web_search_20250305","max_uses":1}]}"#
                ),
                ("/v1/responses", #"{"model":"\#(slug)","input":"hello"}"#),
                ("/v1/responses", responsesWebSearchRequest(slug: slug)),
            ] {
                let result = try await client.execute(
                    uri: path,
                    method: .post,
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .internalServerError)
            }
        }

        #expect(recorder.events.count == 4)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .cancelled })
        #expect(recorder.events.allSatisfy { $0.finalStatus == nil })
        #expect(await transport.requests.isEmpty)
    }

    @Test("Unexpected responder errors record a safe gateway failure before rethrowing")
    func unexpectedResponderErrorRecording() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder,
            dependencies: GatewayResponderDependencies(
                snapshotCapturer: ThrowingGatewaySnapshotCapturer()
            )
        )
        let app = Application(responder: responder)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/models",
                method: .get
            )
            #expect(result.status == .internalServerError)
        }

        let event = try #require(recorder.events.first)
        #expect(event.lifecycle == .failed)
        #expect(event.failure == TrafficFailure(kind: "gateway", message: "Gateway response failed"))
        #expect(event.failure?.message.contains("private-admission") == false)
    }
}

private func waitForGatewayPoolSnapshot(
    _ state: GatewayState,
    timeout: Duration = .seconds(5),
    where predicate: @escaping @Sendable (ProviderRequestPoolSnapshot) -> Bool
) async throws -> ProviderRequestPoolSnapshot {
    try await eventually(
        timeout: timeout,
        description: "the gateway request pool to reach the expected state"
    ) {
        let snapshot = await state.requestPoolSnapshot()
        return predicate(snapshot) ? snapshot : nil
    }
}

private struct ThrowingGatewayAdmitter: GatewayAdmitting {
    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        _ = request
        throw PrivateAdmissionError()
    }
}

private struct ThrowingGatewaySnapshotCapturer: GatewayRoutingSnapshotCapturing {
    func capture(state: GatewayState) async throws -> GatewayRoutingCapture {
        _ = state
        throw PrivateAdmissionError()
    }
}

private struct CancellingGatewayAdmitter: GatewayAdmitting {
    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        _ = request
        throw CancellationError()
    }
}

private struct PrivateAdmissionError: Swift.Error, CustomStringConvertible {
    var description: String {
        "private-admission"
    }
}
