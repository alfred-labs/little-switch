import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Routing changes during credential reads return client-specific queue failures")
    func credentialRoutingInvalidation() async throws {
        for path in ["/v1/messages", "/v1/responses"] {
            let fixture = try makeFixture()
            let slug = try responsesSlug(fixture)
            let transport = RecordingGatewayTransport(responses: [
                path == "/v1/messages"
                    ? response(status: .ok, body: #"{"type":"message","content":[]}"#)
                    : response(
                        status: .ok,
                        body:
                            #"{"id":"chatcmpl_1","created":1,"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#
                    )
            ])
            let recorder = TrafficTestRecorder()
            let responder = GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder,
                dependencies: GatewayResponderDependencies(
                    snapshotCapturer: CredentialInvalidatingSnapshotCapturer()
                )
            )
            let app = Application(responder: responder)
            let body =
                path == "/v1/messages"
                ? #"{"model":"claude-opus-5","messages":[]}"#
                : #"{"model":"\#(slug)","input":"hello"}"#

            try await app.test(.router) { client in
                let result = try await client.execute(
                    uri: path,
                    method: .post,
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .serviceUnavailable)
                #expect(result.headers[.retryAfter] == "30")
                let object = try #require(
                    JSONSerialization.jsonObject(with: Data(result.body.readableBytesView))
                        as? [String: Any]
                )
                let error = try #require(object["error"] as? [String: Any])
                #expect(
                    error["type"] as? String
                        == (path == "/v1/messages" ? "overloaded_error" : "server_error")
                )
            }

            #expect(await transport.requests.isEmpty)
            #expect(await fixture.state.sessionRequestCount == 0)
            let event = try #require(recorder.events.only)
            #expect(event.lifecycle == .failed)
            #expect(event.failure?.kind == "queue")
        }
    }

    @Test("Queue pressure returns retryable client schemas without upstream traffic")
    func queuePressureResponses() async throws {
        for queueError in [
            GatewayAdmissionError.overloaded,
            .timedOut,
            .invalidated,
        ] {
            let fixture = try makeFixture()
            let transport = RecordingGatewayTransport(responses: [])
            let recorder = TrafficTestRecorder()
            let responder = GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder,
                dependencies: GatewayResponderDependencies(
                    admitter: FailingGatewayAdmitter(error: queueError)
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
                #expect(messages.status == .serviceUnavailable)
                #expect(messages.headers[.retryAfter] == "30")
                let anthropic = try #require(
                    JSONSerialization.jsonObject(with: Data(messages.body.readableBytesView))
                        as? [String: Any]
                )
                #expect(
                    (anthropic["error"] as? [String: Any])?["type"] as? String
                        == "overloaded_error"
                )

                let responses = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
                )
                #expect(responses.status == .serviceUnavailable)
                #expect(responses.headers[.retryAfter] == "30")
                let openAI = try #require(
                    JSONSerialization.jsonObject(with: Data(responses.body.readableBytesView))
                        as? [String: Any]
                )
                #expect((openAI["error"] as? [String: Any])?["type"] as? String == "server_error")
            }

            #expect(await transport.requests.isEmpty)
            #expect(recorder.events.count == 2)
            #expect(recorder.events.allSatisfy { $0.lifecycle == .failed })
            #expect(recorder.events.allSatisfy { $0.failure?.kind == "queue" })
            #expect(recorder.events.map(\.client) == [.claude, .codex])
            #expect(recorder.events.allSatisfy { $0.providerName == "z.ai" })
        }
    }

    @Test("Admission captures canonical routes and charges only the queued canonical body")
    func admissionMetadataAndBodyCharge() async throws {
        let fixture = try makeFixture()
        let admissions = CapturingGatewayAdmitter()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: #"{"type":"message","content":[]}"#),
            response(status: .badRequest, body: #"{"error":{"message":"stop"}}"#),
        ])
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(admitter: admissions)
            )
        )
        let messagesBody = Data(
            #"{"model":"claude-opus-5","messages":[{"role":"user","content":"hello"}]}"#.utf8
        )
        let slug = try responsesSlug(fixture)
        let responsesBody = Data(
            #"{"model":"\#(slug)","input":"\#(String(repeating: "compressible ", count: 50))"}"#.utf8
        )
        let compressedResponsesBody = try zstdCompressed(responsesBody)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(bytes: messagesBody)
            )
            #expect(messages.status == .ok)
            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentEncoding: "zstd"],
                body: ByteBuffer(bytes: compressedResponsesBody)
            )
            #expect(responses.status == .badRequest)
        }

        let captured = await admissions.requests
        let upstream = await transport.requests
        try #require(captured.count == 2)
        try #require(upstream.count == 2)
        #expect(captured.map(\.client) == [.claude, .codex])
        #expect(captured[0].modelIdentifier == "claude-opus-5")
        #expect(captured[1].modelIdentifier == slug)
        #expect(captured[0].targetModelID == "glm-5.2")
        #expect(captured[1].targetModelID == "glm-5.2")
        #expect(captured[0].retainedBodyBytes == messagesBody.count)
        #expect(captured[1].retainedBodyBytes == responsesBody.count)
        #expect(captured[1].retainedBodyBytes > compressedResponsesBody.count)
    }

    @Test("Admission shutdown and invariant failures retain distinct safe responses")
    func terminalAdmissionFailureResponses() async throws {
        for scenario in [
            (GatewayAdmissionError.notAcceptingRequests, 503, "Gateway is shutting down"),
            (GatewayAdmissionError.duplicateEventID, 500, "Could not admit request"),
            (GatewayAdmissionError.invalidRetainedBodyBytes, 500, "Could not admit request"),
        ] {
            let fixture = try makeFixture()
            let transport = RecordingGatewayTransport(responses: [])
            let responder = GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    admitter: FailingGatewayAdmitter(error: scenario.0)
                )
            )
            let app = Application(responder: responder)

            try await app.test(.router) { client in
                let result = try await client.execute(
                    uri: "/v1/messages",
                    method: .post,
                    body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
                )
                #expect(Int(result.status.code) == scenario.1)
                #expect(result.headers[.retryAfter] == nil)
                #expect(String(buffer: result.body).contains(scenario.2))
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}

private struct CredentialInvalidatingSnapshotCapturer: GatewayRoutingSnapshotCapturing {
    func capture(state: GatewayState) async throws -> GatewayRoutingCapture {
        let capture = await state.routingCapture()
        _ = await state.replace(
            providers: capture.snapshot.providers,
            mappings: capture.snapshot.mappings,
            codex: capture.snapshot.codex,
            webSearch: capture.snapshot.webSearch,
            credentialChangedProviderIDs: Set(capture.snapshot.providers.map(\.id))
        )
        return capture
    }
}

private struct FailingGatewayAdmitter: GatewayAdmitting {
    let error: GatewayAdmissionError

    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        _ = request
        throw error
    }
}

private actor CapturingGatewayAdmitter: GatewayAdmitting {
    private(set) var requests: [GatewayRequestAdmission] = []

    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        requests.append(request)
    }
}
