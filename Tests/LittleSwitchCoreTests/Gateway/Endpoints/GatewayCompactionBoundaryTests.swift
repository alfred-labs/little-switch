import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Native compaction rejects the local sentinel before contacting OpenAI")
    func compactionSentinelAuthorization() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer \(CodexNativePassthrough.sentinelAPIKey)"],
                body: ByteBuffer(bytes: compactionRequest(model: "gpt-native")))
            #expect(result.status == .unauthorized)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Compaction bounds the summary request and portable response", arguments: [false, true])
    func compactionSizeBoundaries(responseLimit: Bool) async throws {
        let fixture = try makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let largeSummary = compactionSummaryResponse().replacingOccurrences(
            of: "Continue the implementation; the file was read.", with: String(repeating: "summary ", count: 400))
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: largeSummary)])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: responseLimit ? 4_096 : 64,
            requiredAuthorityPort: nil)
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: compactionRequest(model: "z.ai/glm-5.2")))
        let result = try await responder.responsesCompactionResponse(
            plan: plan,
            target: GatewayCompactionTarget(route: target, credential: nil),
            incomingHeaders: [:],
            eventID: UUID())
        #expect(result.status == (responseLimit ? .contentTooLarge : .badRequest))
        #expect(await transport.requests.count == (responseLimit ? 1 : 0))
    }

    @Test("An oversized selected summary fails without a repair or partial response")
    func compactionSelectedSummaryLimit() async throws {
        let fixture = try makeFixture()
        let summary = compactionSummaryResponse().replacingOccurrences(
            of: "Continue the implementation; the file was read.", with: String(repeating: "summary ", count: 2_000))
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: summary)])
        let application = makeApplication(fixture: fixture, transport: transport, maximumRequestBytes: 4_096)
        try await application.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2")))
            #expect(result.status == .contentTooLarge)
            #expect(String(buffer: result.body).contains("Compacted response is too large"))
            #expect(!String(buffer: result.body).contains("little_switch_compaction"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("An unspecified compaction wire follows the learned native capability")
    func compactionDefaultWire() async throws {
        let fixture = try makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        await fixture.state.responsesCapabilities.record(providerID: target.provider.id, supportsNative: true)
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: compactionSummaryResponse())])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: compactionRequest(model: "z.ai/glm-5.2")))
        let turn = try await responder.compactionModelTurn(
            body: plan.summaryRequest(model: target.model.id, stream: false, repair: nil),
            target: GatewayCompactionTarget(route: target, credential: nil),
            incomingHeaders: [:],
            eventID: UUID(),
            attempt: 0)
        #expect(turn.usage.inputTokens == 20)
        #expect(turn.usage.outputTokens == 5)
        let sent = try #require(await transport.requests.first)
        #expect(sent.url.hasSuffix("/responses"))
        #expect(await transport.requests.count == 1)
    }

    @Test("Opaque native state cannot be quoted to a custom summary model")
    func compactionRequiresNativeCheckpointDecoder() async throws {
        let fixture = try makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let body = Data(
            #"{"model":"z.ai/glm-5.2","stream":true,"input":[{"type":"compaction","encrypted_content":"opaque"},{"type":"compaction_trigger"}]}"#
                .utf8)
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: body, providerID: target.provider.id))
        let result = try await responder.responsesCompactionResponse(
            plan: plan,
            target: GatewayCompactionTarget(route: target, credential: nil),
            incomingHeaders: [:],
            eventID: UUID())
        #expect(result.status == .badRequest)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Cancellation while collecting an upstream compaction error remains cancellation")
    func compactionErrorBodyCancellation() async throws {
        let fixture = try makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let transport = RecordingGatewayTransport(responses: [
            failingResponse(status: .tooManyRequests, error: CancellationError())
        ])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil)
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: compactionRequest(model: "z.ai/glm-5.2")))
        await #expect(throws: CancellationError.self) {
            try await responder.responsesCompactionResponse(
                plan: plan,
                target: GatewayCompactionTarget(route: target, credential: nil),
                incomingHeaders: [:],
                eventID: UUID())
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Compaction accepts a streamed Chat summary including a deferred final separator", arguments: [false, true])
    func compactionStreamedChatSummary(deferredSeparator: Bool) async throws {
        let fixture = try makeFixture()
        await fixture.state.responsesCapabilities.record(
            providerID: fixture.snapshot.providers[0].id, supportsNative: false)
        let arguments = #"{"summary":"The marker is preserved.","retain_item_ids":[]}"#
        let frames = try [
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "role": "assistant",
                    "tool_calls": [
                        chatToolDelta(index: 0, id: "summary", name: "create_summary", arguments: arguments)
                    ],
                ])
            ]),
            chatChunkFrame(
                choices: [chatChoice(delta: [:], finishReason: "tool_calls")],
                usage: ["prompt_tokens": 8, "completion_tokens": 3, "total_tokens": 11]),
            chatDoneFrame(),
        ]
        var stream = try #require(String(bytes: chatSSEChunks(frames).reduce(Data(), +), encoding: .utf8))
        if deferredSeparator {
            stream.removeLast(2)
            stream += "\r\r"
        }
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok, headers: ["content-type": "text/event-stream"], chunks: stream.map(String.init))
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: compactionRequest(model: "z.ai/glm-5.2")))
            #expect(result.status == .ok)
            #expect(String(buffer: result.body).contains("The marker is preserved."))
            #expect(String(buffer: result.body).contains("\"total_tokens\":11"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Both continuation destinations enforce their prepared body limit", arguments: [false, true])
    func continuationPreparedBodyLimit(native: Bool) async throws {
        let fixture = try makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: 16,
            requiredAuthorityPort: nil)
        let body = Data(#"{"model":"z.ai/glm-5.2","input":"Continue the conversation."}"#.utf8)
        let result =
            if native {
                try await responder.nativeResponsesResponse(body: body, incomingHeaders: [:], eventID: UUID())
            } else {
                try await responder.admittedResponsesResponse(
                    TransparentResponsesContext(
                        body: body,
                        model: "z.ai/glm-5.2",
                        target: target,
                        credential: nil,
                        incomingHeaders: [:],
                        eventID: UUID(),
                        streaming: false),
                    prepared: PreparedGatewayResponses(body: body, target: target, configuration: .init()),
                    configuration: .init())
            }
        #expect(result.status == .contentTooLarge)
        #expect(await transport.requests.isEmpty)
    }

    @Test("A malformed portable checkpoint is rejected before native forwarding")
    func nativeMalformedPortableCheckpoint() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let body = try responsesStreamData([
            "model": "gpt-native",
            "input": [
                [
                    "type": "compaction",
                    "encrypted_content": #"{"type":"little_switch_compaction","version":999}"#,
                ]
            ],
        ])
        try await makeApplication(fixture: fixture, transport: transport).test(.router) { client in
            let result = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: body))
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.isEmpty)
    }
}
