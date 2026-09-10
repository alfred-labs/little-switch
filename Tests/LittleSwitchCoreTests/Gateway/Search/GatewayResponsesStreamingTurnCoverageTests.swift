import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses streaming turn coverage")
struct GatewayResponsesTurnCoverageTests {
    @Test("Responses live turns map native and adapted stream failures")
    func responsesStreamFailures() async throws {
        let tests = GatewayTests()
        let fixture = try await tests.makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let adapted = try OpenAIResponsesChatCompletions.prepare(
            body: context.prepared.upstreamBody,
            targetModel: context.target.model.id,
            mode: .streaming(toolStream: true)
        )

        for adaptedRequest in [Optional<PreparedResponsesChatCompletionsRequest>.none, adapted] {
            for termination in [DemandTrackedBodyTermination.cancellation, .failure] {
                let response = coverageResponse(
                    DemandTrackedBodySequence(chunks: [], termination: termination),
                    contentType: "text/event-stream"
                )
                var session = ResponsesPublicStreamSession(webSearch: context.prepared)
                var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
                let head = GatewayResponsesLiveModelHead(
                    response: response,
                    adapted: adaptedRequest,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                )
                if termination == .cancellation {
                    await #expect(throws: CancellationError.self) {
                        _ = try await responder.consumeResponsesLiveTurn(
                            head,
                            session: &session,
                            writer: &writer
                        )
                    }
                } else {
                    await #expect(throws: GatewayResponsesLiveError.self) {
                        _ = try await responder.consumeResponsesLiveTurn(
                            head,
                            session: &session,
                            writer: &writer
                        )
                    }
                }
            }
        }

        let native = DemandTrackedBodySequence(chunks: try liveNativeFinalChunks())
        var nativeSession = ResponsesPublicStreamSession(webSearch: context.prepared)
        var nativeWriter: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await responder.consumeResponsesLiveTurn(
                GatewayResponsesLiveModelHead(
                    response: coverageResponse(native, contentType: "text/event-stream"),
                    adapted: nil,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                ),
                session: &nativeSession,
                writer: &nativeWriter
            )
        }

        let chat = DemandTrackedBodySequence(chunks: try liveZAIFinalChunks())
        var chatSession = ResponsesPublicStreamSession(webSearch: context.prepared)
        var chatWriter: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await responder.consumeResponsesLiveTurn(
                GatewayResponsesLiveModelHead(
                    response: coverageResponse(chat, contentType: "text/event-stream"),
                    adapted: adapted,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                ),
                session: &chatSession,
                writer: &chatWriter
            )
        }
    }

    @Test("Responses JSON fallback validates identity, failure, output, and usage")
    func responsesJSONValidation() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let invalid: [[String: Any]] = [
            [:],
            [
                "id": "resp_failed",
                "status": "failed",
                "error": ["code": "", "message": "private"],
            ],
            ["id": "resp_completed"],
        ]
        for object in invalid {
            var session = ResponsesPublicStreamSession(webSearch: context.prepared)
            var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
            let head = GatewayResponsesLiveModelHead(
                response: coverageBytesResponse(
                    try responseData(object),
                    contentType: "application/json"
                ),
                adapted: nil,
                trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
            )
            await #expect(throws: GatewayResponsesLiveError.self) {
                _ = try await responder.consumeResponsesLiveTurn(
                    head,
                    session: &session,
                    writer: &writer
                )
            }
        }
    }

    @Test("Responses JSON fallback maps read, write, terminal, and context failures")
    func responsesJSONFailures() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        for termination in [DemandTrackedBodyTermination.cancellation, .failure] {
            var session = ResponsesPublicStreamSession(webSearch: context.prepared)
            var writer: any ResponseBodyWriter = CoverageThrowingWriter(failure: .none)
            let head = GatewayResponsesLiveModelHead(
                response: coverageResponse(
                    DemandTrackedBodySequence(chunks: [], termination: termination),
                    contentType: "application/json"
                ),
                adapted: nil,
                trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
            )
            if termination == .cancellation {
                await #expect(throws: CancellationError.self) {
                    _ = try await responder.consumeResponsesLiveTurn(
                        head,
                        session: &session,
                        writer: &writer
                    )
                }
            } else {
                await #expect(throws: GatewayResponsesLiveError.self) {
                    _ = try await responder.consumeResponsesLiveTurn(
                        head,
                        session: &session,
                        writer: &writer
                    )
                }
            }
        }

        let completed = try responseData(
            responseObject(
                id: "resp_writer",
                createdAt: 2,
                status: "completed",
                output: [],
                usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
            )
        )
        var writeSession = ResponsesPublicStreamSession(webSearch: context.prepared)
        var writeFailure: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await responder.consumeResponsesLiveTurn(
                GatewayResponsesLiveModelHead(
                    response: coverageBytesResponse(completed, contentType: "application/json"),
                    adapted: nil,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                ),
                session: &writeSession,
                writer: &writeFailure
            )
        }

        let failed = try responseData([
            "id": "resp_terminal",
            "object": "response",
            "status": "failed",
            "error": ["code": "provider_error", "message": "private"],
        ])
        var failedSession = ResponsesPublicStreamSession(webSearch: context.prepared)
        let failedRecorder = StreamingStageRecorder()
        var failedWriter: any ResponseBodyWriter = ObservingResponseBodyWriter(
            recorder: failedRecorder
        )
        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await responder.consumeResponsesLiveTurn(
                GatewayResponsesLiveModelHead(
                    response: coverageBytesResponse(failed, contentType: "application/json"),
                    adapted: nil,
                    trace: responder.upstreamResponseTrace(eventID: context.eventID, attempt: 0)
                ),
                session: &failedSession,
                writer: &failedWriter
            )
        }
    }
}
