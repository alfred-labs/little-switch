import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Native Responses failures preserve builder, admission, and transport semantics")
    func nativeResponsesFailures() async throws {
        let missingCredential = try responsesProviderFixture(includeSecret: false)
        let missingSlug = try responsesSlug(missingCredential)
        let anonymousTransport = RecordingGatewayTransport(responses: [])
        try await makeApplication(
            fixture: missingCredential,
            transport: anonymousTransport
        ).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(missingSlug)","input":"hello"}"#)
            )
            #expect(result.status == .badGateway)
        }
        // The anonymous request left for the provider with no auth header.
        let anonymousRequest = await anonymousTransport.requests.first
        #expect(anonymousRequest?.headers["authorization"].isEmpty == true)

        let stopped = try responsesProviderFixture(includeSecret: true)
        await stopped.state.stopAdmissions()
        let stoppedSlug = try responsesSlug(stopped)
        try await makeApplication(
            fixture: stopped,
            transport: RecordingGatewayTransport(responses: [])
        ).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(stoppedSlug)","input":"hello"}"#)
            )
            #expect(result.status == .serviceUnavailable)
        }

        let ready = try responsesProviderFixture(includeSecret: true)
        let readySlug = try responsesSlug(ready)
        let failures: [(any UpstreamTransport, HTTPResponse.Status)] = [
            (
                FailingGatewayTransport(error: GatewayTestError.privateFailure),
                .badGateway
            ),
            (CancellingGatewayTransport(), .internalServerError),
        ]
        for (transport, expected) in failures {
            try await makeApplication(fixture: ready, transport: transport).test(.router) { client in
                let result = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    body: ByteBuffer(string: #"{"model":"\#(readySlug)","input":"hello"}"#)
                )
                #expect(result.status == expected)
            }
        }
    }

    @Test("z.ai Responses adapter rejects invalid input, upstream status, and invalid bodies safely")
    func adaptedResponsesFailures() async throws {
        let fixture = try makeFixture()
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let target = try #require(fixture.snapshot.resolveCodex(model: slug))
        let root = ["model": slug, "input": "hello"]
        let body = try JSONSerialization.data(withJSONObject: root)
        let context = TransparentResponsesContext(
            body: body,
            model: slug,
            target: target,
            credential: "selected-secret",
            incomingHeaders: [:],
            eventID: UUID(),
            streaming: false
        )

        let invalidContext = TransparentResponsesContext(
            body: Data(#"{"model":"route","input":1}"#.utf8),
            model: slug,
            target: target,
            credential: "selected-secret",
            incomingHeaders: [:],
            eventID: UUID(),
            streaming: false
        )
        let noTransport = RecordingGatewayTransport(responses: [])
        let invalidResponder = GatewayResponder(
            state: fixture.state,
            transport: noTransport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        #expect(
            try await invalidResponder.chatCompletionsResponsesResponse(invalidContext).status
                == .badRequest
        )

        let unbuildableContext = TransparentResponsesContext(
            body: context.body,
            model: context.model,
            target: unbuildableTarget(context.target),
            credential: context.credential,
            incomingHeaders: context.incomingHeaders,
            eventID: UUID(),
            streaming: false
        )
        #expect(
            try await invalidResponder.chatCompletionsResponsesResponse(unbuildableContext).status
                == .serviceUnavailable
        )

        let failures: [(HTTPClientResponse, HTTPResponse.Status)] = [
            (response(status: .unauthorized, body: "private"), .unauthorized),
            (response(status: .ok, body: "{}"), .badGateway),
            (failingResponse(error: GatewayTestError.privateFailure), .badGateway),
            (failingResponse(status: .badGateway, error: GatewayTestError.privateFailure), .badGateway),
        ]
        for (upstream, expected) in failures {
            let responder = GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: [upstream]),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil
            )
            #expect(try await responder.chatCompletionsResponsesResponse(context).status == expected)
        }

        let cancellingBodyResponder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                failingResponse(status: .badGateway, error: CancellationError())
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        await #expect(throws: CancellationError.self) {
            _ = try await cancellingBodyResponder.chatCompletionsResponsesResponse(context)
        }
    }

    private func responsesProviderFixture(includeSecret: Bool) throws -> GatewayFixture {
        let base = try makeFixture()
        let original = try #require(base.snapshot.providers.first)
        let provider = Provider(
            id: original.id,
            name: "OpenAI compatible",
            baseURL: "https://example.com/api",
            authMode: original.authMode,
            models: original.models
        )
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: [provider],
            mappings: base.snapshot.mappings,
            codex: base.snapshot.codex,
            webSearch: base.snapshot.webSearch
        )
        let secrets = MemorySecretStore()
        if includeSecret {
            try secrets.write("selected-secret", providerID: provider.id)
        }
        return GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: secrets
        )
    }
}

@Suite("Gateway Responses adapter failures")
struct GatewayResponsesAdapterFailureTests {
    @Test("Configured Chat stream limit rejects cumulative frames safely")
    func cumulativeChatStreamLimitIsSafe() async throws {
        let fixture = try GatewayTests().makeFixture()
        let frames = try simpleChatFrames(finishReason: "stop")
        let maximumErrorBytes = try minimumChatFrameWireLimit(frames)
        let upstreamBody = DemandTrackedBodySequence(chunks: chatSSEChunks(frames))
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                gatewayChatStreamingResponse(upstreamBody)
            ]),
            secretStore: fixture.secrets,
            maximumErrorBytes: maximumErrorBytes,
            requiredAuthorityPort: nil
        )

        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(fixture: fixture, includeTools: false)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }

        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        #expect(events.last?.name == "response.failed")
        #expect(!events.contains { $0.name == "response.completed" })
        #expect(await recorder.finishCount == 1)
    }

    @Test("A committed malformed Chat stream emits one safe failed lifecycle")
    func postCommitFailureIsSafe() async throws {
        let fixture = try GatewayTests().makeFixture()
        let privateBody = Data(#"data: {"secret":"provider-body"}\n\n"#.utf8)
        let upstreamBody = DemandTrackedBodySequence(chunks: [privateBody])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                gatewayChatStreamingResponse(upstreamBody)
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(
                fixture: fixture,
                includeTools: false
            )
        )
        #expect(response.status == .ok)
        #expect(response.body.contentLength == nil)
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }

        let body = await recorder.body
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(events.map(\.name) == ["error", "response.failed"])
        #expect(events.map(\.sequenceNumber) == [0, 1])
        #expect(
            Set(events[0].payload.keys)
                == ["type", "sequence_number", "code", "message", "param"]
        )
        #expect(events[0].payload["message"] as? String == "Internal server error")
        let failed = try #require(events[1].payload["response"] as? [String: Any])
        #expect((failed["id"] as? String)?.hasPrefix("resp_") == true)
        #expect(failed["status"] as? String == "failed")
        #expect(events.last?.name == "response.failed")
        let stream = String(bytes: body, encoding: .utf8) ?? ""
        #expect(!stream.contains("provider-body"))
        #expect(!stream.contains("secret"))
        #expect(await recorder.finishCount == 1)
    }

    @Test("Cancellation after the response head emits no protocol failure")
    func postCommitCancellationIsSilent() async throws {
        let fixture = try GatewayTests().makeFixture()
        let upstreamBody = DemandTrackedBodySequence(
            chunks: [],
            termination: .cancellation
        )
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                gatewayChatStreamingResponse(upstreamBody)
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(
                fixture: fixture,
                includeTools: false
            )
        )
        let recorder = StreamingStageRecorder()

        await #expect(throws: CancellationError.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }
        let stream = await recorder.bodyString
        #expect(!stream.contains("event: error"))
        #expect(!stream.contains("response.failed"))
        #expect(await recorder.finishCount == 0)
    }

    @Test("ZAI context exhaustion emits Codex's native context-length code")
    func contextLengthFailureUsesNativeCode() async throws {
        let fixture = try GatewayTests().makeFixture()
        let terminal = try contextExhaustionSSE()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                gatewayChatStreamingResponse(
                    DemandTrackedBodySequence(chunks: [terminal])
                )
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(fixture: fixture, includeTools: false)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }

        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        #expect(events.map(\.name) == ["error", "response.failed"])
        #expect(events[0].payload["code"] as? String == "context_length_exceeded")
        let failed = try #require(events[1].payload["response"] as? [String: Any])
        #expect(
            (failed["error"] as? [String: Any])?["code"] as? String
                == "context_length_exceeded"
        )
    }

    @Test("A JSON fallback failure also marks the committed stream failed")
    func jsonFallbackFailureUsesCommittedSentinel() async throws {
        let fixture = try GatewayTests().makeFixture()
        let providerBody = try contextExhaustionJSON()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(status: .ok, body: providerBody)
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(fixture: fixture, includeTools: false)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }

        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        #expect(events.map(\.name).suffix(2) == ["error", "response.failed"])
        #expect(events[events.count - 2].payload["code"] as? String == "context_length_exceeded")
        #expect(await recorder.finishCount == 1)
    }
}

private func contextExhaustionSSE() throws -> Data {
    let chunk: [String: Any] = [
        "id": "chatcmpl_context",
        "object": "chat.completion.chunk",
        "created": 123,
        "model": "glm-5.2",
        "choices": [
            [
                "index": 0,
                "delta": ["role": "assistant", "content": ""],
                "finish_reason": "model_context_window_exceeded",
            ]
        ],
        "usage": [
            "prompt_tokens": 200_000,
            "completion_tokens": 0,
            "total_tokens": 200_000,
        ],
    ]
    var wire = Data("data: ".utf8)
    wire.append(try JSONSerialization.data(withJSONObject: chunk, options: [.sortedKeys]))
    wire.append(Data("\n\ndata: [DONE]\n\n".utf8))
    return wire
}

private func contextExhaustionJSON() throws -> String {
    let response: [String: Any] = [
        "id": "chatcmpl_json_context",
        "object": "chat.completion",
        "created": 123,
        "model": "glm-5.2",
        "choices": [
            [
                "index": 0,
                "finish_reason": "model_context_window_exceeded",
                "message": ["role": "assistant", "content": ""],
            ]
        ],
        "usage": [
            "prompt_tokens": 200_000,
            "completion_tokens": 0,
            "total_tokens": 200_000,
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    return try #require(String(data: data, encoding: .utf8))
}

/// A target whose base URL cannot produce a request, so the responder has to
/// report that the provider is not ready instead of calling upstream.
func unbuildableTarget(_ target: CodexModelTarget) -> CodexModelTarget {
    var provider = target.provider
    provider.baseURL = "not a url"
    return CodexModelTarget(provider: provider, model: target.model)
}
