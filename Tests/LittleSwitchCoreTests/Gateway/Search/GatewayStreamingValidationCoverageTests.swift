import Foundation
import Hummingbird
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway streaming validation coverage")
struct GatewayStreamingValidationCoverageTests {
    @Test("Public publishers reject a non-start event before session identity")
    func invalidInitialEvents() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)

        var anthropic = AnthropicPublicStreamSession(originalModel: "original")
        await #expect(throws: GatewayAnthropicLiveError.self) {
            try await responder.publishAnthropicLiveEvent(
                .messageStop,
                session: &anthropic,
                writer: &writer
            )
        }

        let responsesContext = try liveResponsesSearchContext(fixture: fixture)
        var responses = ResponsesPublicStreamSession(webSearch: responsesContext.prepared)
        await #expect(throws: GatewayResponsesLiveError.self) {
            try await responder.publishResponsesLiveEvent(
                .passthrough(type: "response.in_progress", payloadJSON: Data("{}".utf8)),
                session: &responses,
                writer: &writer
            )
        }

        let chatContext = try gatewayLiveChatContext(fixture: fixture, includeTools: false)
        let chatPrepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatContext.body,
            targetModel: chatContext.target.model.id,
            mode: .streaming(toolStream: true)
        )
        var chat = ResponsesPublicStreamSession(chatCompletions: chatPrepared)
        do {
            try await responder.publishLiveChatCompletionsEvent(
                .passthrough(type: "response.in_progress", payloadJSON: Data("{}".utf8)),
                session: &chat,
                writer: &writer
            )
            Issue.record("Expected the invalid initial Chat event to fail")
        } catch {
            #expect(String(describing: error).contains("unexpectedFirstEvent"))
        }
    }

    @Test("Anthropic JSON fallback validates content and preserves its stop reason")
    func anthropicJSONContentAndStopReason() throws {
        let invalidTurn = AnthropicModelTurn(
            id: "msg_invalid_content",
            contentJSON: Data("{}".utf8),
            stopReason: "end_turn",
            stopSequenceJSON: nil,
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 1),
            webSearchCall: nil
        )
        #expect(throws: GatewayAnthropicLiveError.self) {
            _ = try anthropicLiveEvents(for: invalidTurn)
        }

        let validTurn = AnthropicModelTurn(
            id: "msg_valid_content",
            contentJSON: Data("[]".utf8),
            stopReason: "end_turn",
            stopSequenceJSON: nil,
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 1),
            webSearchCall: nil
        )
        let events = try anthropicLiveEvents(for: validTurn)
        guard events.count == 3 else {
            Issue.record("Expected start, delta, and stop events")
            return
        }
        guard case .messageDelta(let deltaJSON, _) = events[1] else {
            Issue.record("Expected a message delta")
            return
        }
        let delta = try #require(
            JSONSerialization.jsonObject(with: deltaJSON) as? [String: Any]
        )
        #expect(delta["stop_reason"] as? String == "end_turn")

        let openTurn = AnthropicModelTurn(
            id: "msg_open_content",
            contentJSON: Data("[]".utf8),
            stopReason: nil,
            stopSequenceJSON: nil,
            usage: AnthropicUsage(inputTokens: 1, outputTokens: 1),
            webSearchCall: nil
        )
        let openEvents = try anthropicLiveEvents(for: openTurn)
        guard openEvents.count == 3,
            case .messageDelta(let openDeltaJSON, _) = openEvents[1]
        else {
            Issue.record("Expected an open message delta")
            return
        }
        let openDelta = try #require(
            JSONSerialization.jsonObject(with: openDeltaJSON) as? [String: Any]
        )
        #expect(openDelta["stop_reason"] is NSNull)
    }

    @Test("Anthropic SSE publishing maps a failed client write")
    func anthropicSSEClientWriteFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        var session = AnthropicPublicStreamSession(originalModel: "original")
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        let response = coverageBytesResponse(
            try gatewayProviderSSE(realisticProviderFrames()),
            contentType: "text/event-stream"
        )
        await #expect(throws: GatewayAnthropicLiveError.self) {
            _ = try await responder.consumeAnthropicLiveTurn(
                response,
                context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                session: &session,
                writer: &writer
            )
        }
    }

    @Test("Native failed JSON preserves context length after bounded re-encoding")
    func nativeJSONContextLengthFallback() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)
        let failed = try responseData([
            "id": "resp_context",
            "object": "response",
            "status": "failed",
            "error": ["code": "context_length_exceeded", "message": "private"],
        ])
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            maximumErrorBytes: failed.count
        )
        var session = ResponsesPublicStreamSession(webSearch: context.prepared)
        var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
        await #expect(throws: OpenAIResponsesChatCompletions.Error.self) {
            _ = try await responder.consumeResponsesLiveTurn(
                GatewayResponsesLiveModelHead(
                    response: coverageBytesResponse(failed, contentType: "application/json"),
                    adapted: nil,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                ),
                session: &session,
                writer: &writer
            )
        }
    }
}
