import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic streaming turn coverage")
struct GatewayAnthropicTurnCoverageTests {
    @Test("Anthropic live turns map stream, JSON, and writer failures")
    func anthropicTurnFailures() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        for contentType in ["text/event-stream", "application/json"] {
            var cancellationSession = AnthropicPublicStreamSession(originalModel: "original")
            var cancellationWriter: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
            await #expect(throws: CancellationError.self) {
                _ = try await responder.consumeAnthropicLiveTurn(
                    coverageResponse(
                        DemandTrackedBodySequence(chunks: [], termination: .cancellation),
                        contentType: contentType
                    ),
                    context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                    session: &cancellationSession,
                    writer: &cancellationWriter
                )
            }

            var failureSession = AnthropicPublicStreamSession(originalModel: "original")
            var failureWriter: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
            await #expect(throws: GatewayAnthropicLiveError.self) {
                _ = try await responder.consumeAnthropicLiveTurn(
                    coverageResponse(
                        DemandTrackedBodySequence(chunks: [], termination: .failure),
                        contentType: contentType
                    ),
                    context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                    session: &failureSession,
                    writer: &failureWriter
                )
            }
        }

        let validJSON = Data(
            anthropicModelResponse(
                id: "msg_writer",
                content: [["type": "text", "text": "writer"]],
                stopReason: "end_turn"
            ).utf8
        )
        for failure in [CoverageWriterFailure.cancellation, .error] {
            var session = AnthropicPublicStreamSession(originalModel: "original")
            var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: failure)
            if failure == .cancellation {
                await #expect(throws: CancellationError.self) {
                    _ = try await responder.consumeAnthropicLiveTurn(
                        coverageBytesResponse(validJSON, contentType: "application/json"),
                        context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                        session: &session,
                        writer: &writer
                    )
                }
            } else {
                await #expect(throws: GatewayAnthropicLiveError.self) {
                    _ = try await responder.consumeAnthropicLiveTurn(
                        coverageBytesResponse(validJSON, contentType: "application/json"),
                        context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                        session: &session,
                        writer: &writer
                    )
                }
            }
        }
    }

    @Test("Anthropic JSON fallback rejects empty block types and missing tool input")
    func anthropicJSONBlockValidation() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let malformedBlocks: [[[String: Any]]] = [
            [["type": ""]],
            [["type": "tool_use", "id": "tool", "name": "weather"]],
        ]
        for blocks in malformedBlocks {
            let data = Data(
                anthropicModelResponse(
                    id: "msg_invalid",
                    content: blocks,
                    stopReason: "end_turn"
                ).utf8
            )
            var session = AnthropicPublicStreamSession(originalModel: "original")
            var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
            await #expect(throws: GatewayAnthropicLiveError.self) {
                _ = try await responder.consumeAnthropicLiveTurn(
                    coverageBytesResponse(data, contentType: "application/json"),
                    context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
                    session: &session,
                    writer: &writer
                )
            }
        }
    }

    @Test("A leading Anthropic ping is ignored before the public session starts")
    func leadingAnthropicPing() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let frames =
            [try providerFrame("ping", ["type": "ping"])]
            + (try realisticProviderFrames())
        var session = AnthropicPublicStreamSession(originalModel: "original")
        let recorder = StreamingStageRecorder()
        var writer: any ResponseBodyWriter = ObservingResponseBodyWriter(recorder: recorder)
        let turn = try await responder.consumeAnthropicLiveTurn(
            coverageBytesResponse(
                try gatewayProviderSSE(frames),
                contentType: "text/event-stream"
            ),
            context: AnthropicLiveTurnContext(attempt: 0, eventID: UUID()),
            session: &session,
            writer: &writer
        )
        #expect(turn.id == "msg_provider")
        #expect((await recorder.bodyString).contains("event: message_start"))
    }

}
