import Foundation
import Hummingbird
import Testing

@testable import LittleSwitchCore

@Suite("Gateway SSE EOF frame handling")
struct GatewaySSEFinishFrameTests {
    @Test("Anthropic consumes a CR-only message stop at EOF exactly once")
    func anthropicTerminalAtEOF() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let upstream = try deferredCRFinalFrame([
            gatewayProviderSSE(realisticProviderFrames())
        ])
        var session = AnthropicPublicStreamSession(originalModel: "original")
        let recorder = StreamingStageRecorder()
        var writer: any ResponseBodyWriter = ObservingResponseBodyWriter(recorder: recorder)

        let turn = try await responder.consumeAnthropicLiveTurn(
            coverageBytesResponse(upstream, contentType: "text/event-stream"),
            context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
            session: &session,
            writer: &writer
        )

        #expect(turn.id == "msg_provider")
        try await responder.writeAnthropicLiveFrames(
            try session.finish(turn: turn, usage: turn.usage),
            to: &writer
        )
        #expect(occurrences(of: "event: message_stop", in: await recorder.bodyString) == 1)
    }

    @Test("Native Responses consumes a CR-only completed frame at EOF exactly once")
    func nativeResponsesTerminalAtEOF() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        var session = ResponsesPublicStreamSession(webSearch: context.prepared)
        let recorder = StreamingStageRecorder()
        var writer: any ResponseBodyWriter = ObservingResponseBodyWriter(recorder: recorder)

        let turn = try await responder.consumeResponsesLiveTurn(
            GatewayResponsesLiveModelHead(
                response: coverageBytesResponse(
                    try deferredCRFinalFrame(liveNativeFinalChunks()),
                    contentType: "text/event-stream"
                ),
                adapted: nil,
                trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
            ),
            session: &session,
            writer: &writer
        )

        #expect(turn.id == "resp_native_final")
        try await responder.writeResponsesLiveFrames(
            try session.finish(responseJSON: turn.rootJSON, usage: turn.usage),
            to: &writer
        )
        #expect(try await responseTerminalCount(recorder) == 1)
    }

    @Test("Adapted Z.AI consumes a CR-only done frame at EOF exactly once")
    func adaptedZAITerminalAtEOF() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: context.prepared.upstreamBody,
            targetModel: context.target.model.id,
            mode: .streaming(toolStream: true)
        )
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        var session = ResponsesPublicStreamSession(webSearch: context.prepared)
        let recorder = StreamingStageRecorder()
        var writer: any ResponseBodyWriter = ObservingResponseBodyWriter(recorder: recorder)

        let turn = try await responder.consumeResponsesLiveTurn(
            GatewayResponsesLiveModelHead(
                response: coverageBytesResponse(
                    try deferredCRFinalFrame(liveZAIFinalChunks()),
                    contentType: "text/event-stream"
                ),
                adapted: prepared,
                trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
            ),
            session: &session,
            writer: &writer
        )

        #expect(turn.webSearchCall == nil)
        try await responder.writeResponsesLiveFrames(
            try session.finish(responseJSON: turn.rootJSON, usage: turn.usage),
            to: &writer
        )
        #expect(try await responseTerminalCount(recorder) == 1)
    }

    @Test("Transparent Z.AI consumes a CR-only done frame at EOF exactly once")
    func transparentZAITerminalAtEOF() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [
                coverageBytesResponse(
                    try deferredCRFinalFrame(gatewayChatCompletionChunks()),
                    contentType: "text/event-stream"
                )
            ])
        )
        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(fixture: fixture, includeTools: false)
        )
        let recorder = StreamingStageRecorder()

        try await response.body.write(ObservingResponseBodyWriter(recorder: recorder))

        #expect(try await responseTerminalCount(recorder) == 1)
        #expect(await recorder.finishCount == 1)
    }
}

private func deferredCRFinalFrame(_ chunks: [Data]) throws -> Data {
    var body = chunks.reduce(into: Data()) { $0.append($1) }
    try #require(body.suffix(2).elementsEqual(Data("\n\n".utf8)))
    body.removeLast(2)
    body.append(Data("\r\r".utf8))
    return body
}

private func occurrences(of needle: String, in value: String) -> Int {
    value.components(separatedBy: needle).count - 1
}

private func responseTerminalCount(_ recorder: StreamingStageRecorder) async throws -> Int {
    try await ResponsesStreamingTestSupport.events(recorder.body)
        .filter { $0.name == "response.completed" }
        .count
}
