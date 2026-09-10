import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import LittleSwitchCore

@Suite("Gateway permit lifecycle")
struct GatewayPermitLifecycleTests {
    @Test("A permit stays active through response creation and finishes after body success")
    func successfulBody() async throws {
        let fixture = permitLifecycleFixture()
        let eventID = UUID()
        try await admitPermit(eventID, fixture: fixture)
        let response = recordedPermitResponse(
            fixture: fixture,
            eventID: eventID,
            body: ResponseBody(byteBuffer: ByteBuffer(string: "done"))
        )

        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        #expect(try await responseBodyData(response.body) == Data("done".utf8))
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)
    }

    @Test("Every response-body terminal path releases its permit")
    func terminalBodyPaths() async throws {
        let fixture = permitLifecycleFixture()

        let committedID = UUID()
        try await admitPermit(committedID, fixture: fixture)
        let committed = recordedPermitResponse(
            fixture: fixture,
            eventID: committedID,
            body: ResponseBody(contentLength: nil) { writer in
                try await writer.write(ByteBuffer(string: "safe"))
                try await writer.finish(nil)
                throw GatewayCommittedStreamFailure()
            }
        )
        #expect(try await responseBodyData(committed.body) == Data("safe".utf8))
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)

        let cancellationID = UUID()
        try await admitPermit(cancellationID, fixture: fixture)
        let cancelled = recordedPermitResponse(
            fixture: fixture,
            eventID: cancellationID,
            body: ResponseBody(contentLength: nil) { _ in
                throw CancellationError()
            }
        )
        await #expect(throws: CancellationError.self) {
            _ = try await responseBodyData(cancelled.body)
        }
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)

        let failureID = UUID()
        try await admitPermit(failureID, fixture: fixture)
        let failed = recordedPermitResponse(
            fixture: fixture,
            eventID: failureID,
            body: ResponseBody(contentLength: nil) { _ in
                throw PermitLifecycleError.injected
            }
        )
        await #expect(throws: PermitLifecycleError.injected) {
            _ = try await responseBodyData(failed.body)
        }
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 0)
    }

    @Test("Discarding an unconsumed response schedules the same idempotent finish")
    func discardedBody() async throws {
        let fixture = permitLifecycleFixture()
        let eventID = UUID()
        try await admitPermit(eventID, fixture: fixture)
        var response: Response? = recordedPermitResponse(
            fixture: fixture,
            eventID: eventID,
            body: ResponseBody(byteBuffer: ByteBuffer(string: "discarded"))
        )
        #expect(response != nil)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)

        response = nil
        let idle: ProviderRequestPoolSnapshot = try await eventually(
            description: "the discarded response permit to finish"
        ) {
            let snapshot = await fixture.state.requestPoolSnapshot()
            return snapshot.totalRunning == 0 ? snapshot : nil
        }
        #expect(idle.totalRunning == 0)
    }

    @Test("A routed request holds its real pool permit until the client body finishes")
    func routedResponseBodyHoldsPermit() async throws {
        let firstBody = #"{"type":"message","content":[{"type":"text","text":"first"}]}"#
        let secondBody = #"{"type":"message","content":[{"type":"text","text":"second"}]}"#
        let fixture = permitLifecycleFixture(responses: [
            response(status: .ok, body: firstBody),
            response(status: .ok, body: secondBody),
        ])
        let firstTask = routedPermitResponseTask(fixture.responder, ordinal: 1)
        defer { firstTask.cancel() }

        let firstResponse = try await valueWithinTimeout(
            firstTask,
            description: "the first routed response head"
        )
        #expect(firstResponse.status == .ok)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        #expect((await fixture.state.requestPoolSnapshot()).totalWaiting == 0)
        #expect(await fixture.transport.requests.count == 1)

        let secondTask = routedPermitResponseTask(fixture.responder, ordinal: 2)
        defer { secondTask.cancel() }
        let queued: ProviderRequestPoolSnapshot = try await eventually(
            description: "the second routed request to queue behind the first response body"
        ) {
            let snapshot = await fixture.state.requestPoolSnapshot()
            return snapshot.totalRunning == 1 && snapshot.totalWaiting == 1
                ? snapshot : nil
        }
        #expect(queued.totalRunning == 1)
        #expect(queued.totalWaiting == 1)
        #expect(await fixture.transport.requests.count == 1)

        #expect(try await responseBodyData(firstResponse.body) == Data(firstBody.utf8))
        let secondResponse = try await valueWithinTimeout(
            secondTask,
            description: "the second routed response after the first body finished"
        )
        #expect(secondResponse.status == .ok)
        let requests = await fixture.transport.requests
        #expect(requests.count == 2)
        #expect(String(data: requests[0].body, encoding: .utf8)?.contains(#""ordinal":1"#) == true)
        #expect(String(data: requests[1].body, encoding: .utf8)?.contains(#""ordinal":2"#) == true)
        #expect((await fixture.state.requestPoolSnapshot()).totalRunning == 1)
        #expect((await fixture.state.requestPoolSnapshot()).totalWaiting == 0)

        #expect(try await responseBodyData(secondResponse.body) == Data(secondBody.utf8))
        let idle: ProviderRequestPoolSnapshot = try await eventually(
            description: "both routed request permits to finish"
        ) {
            let snapshot = await fixture.state.requestPoolSnapshot()
            return snapshot.totalRunning == 0 && snapshot.totalWaiting == 0
                ? snapshot : nil
        }
        #expect(idle.totalRunning == 0)
        #expect(idle.totalWaiting == 0)
    }
}

private struct PermitLifecycleFixture {
    let provider: Provider
    let state: GatewayState
    let responder: GatewayResponder
    let transport: RecordingGatewayTransport
}

private func permitLifecycleFixture(
    responses: [HTTPClientResponse] = []
) -> PermitLifecycleFixture {
    let provider = Provider(
        id: UUID(),
        name: "Permit provider",
        baseURL: "https://example.com",
        authMode: .none,
        models: [DiscoveredModel(id: "model")],
        maximumParallelRequests: 1
    )
    let snapshot = RoutingSnapshot(
        generation: 0,
        providers: [provider],
        mappings: [
            "claude-sonnet-5": ModelMapping(
                providerID: provider.id,
                modelID: "model"
            )
        ]
    )
    let state = GatewayState(snapshot: snapshot)
    let transport = RecordingGatewayTransport(responses: responses)
    return PermitLifecycleFixture(
        provider: provider,
        state: state,
        responder: GatewayResponder(
            state: state,
            transport: transport,
            secretStore: MemorySecretStore(),
            requiredAuthorityPort: nil
        ),
        transport: transport
    )
}

private func routedPermitResponseTask(
    _ responder: GatewayResponder,
    ordinal: Int
) -> Task<Response, any Error> {
    let request = Request(
        head: HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "localhost",
            path: "/v1/messages"
        ),
        body: RequestBody(
            buffer: ByteBuffer(
                string:
                    #"{"model":"claude-sonnet-5","metadata":{"ordinal":\#(ordinal)},"messages":[]}"#
            )
        )
    )
    return Task {
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: EmbeddedChannel(),
                logger: Logger(label: #function)
            )
        )
        return try await responder.respond(to: request, context: context)
    }
}

private func admitPermit(
    _ eventID: UUID,
    fixture: PermitLifecycleFixture
) async throws {
    try await fixture.state.admit(
        GatewayRequestAdmission(
            eventID: eventID,
            capture: await fixture.state.routingCapture(),
            client: .claude,
            modelIdentifier: "claude-sonnet-5",
            providerID: fixture.provider.id,
            targetModelID: "model",
            retainedBodyBytes: 1
        )
    )
}

private func recordedPermitResponse(
    fixture: PermitLifecycleFixture,
    eventID: UUID,
    body: ResponseBody
) -> Response {
    fixture.responder.recordingClientResponse(
        Response(status: .ok, body: body),
        eventID: eventID,
        permitCompletion: GatewayPermitCompletionGuard(
            state: fixture.state,
            eventID: eventID
        )
    )
}

private enum PermitLifecycleError: Swift.Error, Equatable {
    case injected
}
