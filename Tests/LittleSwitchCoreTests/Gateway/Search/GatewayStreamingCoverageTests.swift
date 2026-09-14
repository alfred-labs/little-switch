import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway streaming defensive coverage")
struct GatewayStreamingCoverageTests {
    @Test("Live projectors select their streaming encoders")
    func liveProjectors() async throws {
        let tests = GatewayTests()
        let anthropicFixture = try tests.makeWebSearchFixture()
        let anthropicContext = try tests.gatewayLiveContext(fixture: anthropicFixture)
        let anthropicTurn = try AnthropicWebSearch.parseModelTurn(
            Data(
                anthropicModelResponse(
                    id: "msg_coverage",
                    content: [["type": "text", "text": "covered"]],
                    stopReason: "end_turn"
                ).utf8
            )
        )
        let anthropic = try LiveGatewayWebSearchProjector().anthropicResponse(
            prepared: anthropicContext.prepared,
            traces: [],
            finalTurn: anthropicTurn,
            usage: anthropicTurn.usage
        )
        #expect(
            String(bytes: anthropic, encoding: .utf8)?.contains("event: message_start") == true
        )

        let responsesFixture = try await tests.makeResponsesWebSearchFixture()
        let responsesContext = try liveResponsesSearchContext(fixture: responsesFixture)
        let responsesRoot = responseObject(
            id: "resp_coverage",
            createdAt: 1,
            status: "completed",
            output: [],
            usage: ResponsesUsage(inputTokens: 1, outputTokens: 2)
        )
        let responsesTurn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(responsesRoot)
        )
        let responses = try LiveGatewayWebSearchProjector().responsesResponse(
            prepared: responsesContext.prepared,
            traces: [],
            finalTurn: responsesTurn,
            usage: responsesTurn.usage
        )
        #expect(String(bytes: responses, encoding: .utf8)?.contains("response.created") == true)
    }

    @Test("Low-level live writers preserve cancellation and hide write failures")
    func lowLevelWriters() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let frame = Data("coverage".utf8)

        var anthropicCancellation: any ResponseBodyWriter = CoverageThrowingWriter(
            failure: .cancellation
        )
        await #expect(throws: CancellationError.self) {
            try await responder.writeAnthropicLiveFrames(
                [frame],
                to: &anthropicCancellation
            )
        }
        var anthropicFailure: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        await #expect(throws: GatewayAnthropicLiveError.self) {
            try await responder.writeAnthropicLiveFrames([frame], to: &anthropicFailure)
        }

        var responsesCancellation: any ResponseBodyWriter = CoverageThrowingWriter(
            failure: .cancellation
        )
        await #expect(throws: CancellationError.self) {
            try await responder.writeResponsesLiveFrames(
                [frame],
                to: &responsesCancellation
            )
        }
        var responsesFailure: any ResponseBodyWriter = CoverageThrowingWriter(failure: .error)
        await #expect(throws: GatewayResponsesLiveError.self) {
            try await responder.writeResponsesLiveFrames([frame], to: &responsesFailure)
        }
    }

    @Test("Anthropic live head maps readiness, transport failure, and cancellation")
    func anthropicLiveHeadFailures() async throws {
        let tests = GatewayTests()
        let fixture = try tests.makeWebSearchFixture()
        let context = try tests.gatewayLiveContext(fixture: fixture)

        let unready = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let unreadyResult = try await unready.liveWebSearchResponse(
            context: anthropicContext(context, providerBaseURL: "not-a-provider-url"),
            searchCredential: nil
        )
        #expect(unreadyResult.status == .serviceUnavailable)

        let failed = coverageResponder(
            fixture: fixture,
            transport: FailingGatewayTransport(error: .privateFailure)
        )
        let failedResult = try await failed.liveWebSearchResponse(
            context: context,
            searchCredential: nil
        )
        #expect(failedResult.status == .badGateway)

        let cancelled = coverageResponder(
            fixture: fixture,
            transport: CancellingGatewayTransport()
        )
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.liveWebSearchResponse(
                context: context,
                searchCredential: nil
            )
        }
    }

    @Test("Responses live head maps every preparation and transport boundary")
    func responsesLiveHeadFailures() async throws {
        let tests = GatewayTests()
        let fixture = try await tests.makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)

        let unready = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let unreadyResult = try await unready.liveResponsesWebSearchResponse(
            context: responsesContext(context, providerBaseURL: "not-a-provider-url")
        )
        #expect(unreadyResult.status == .serviceUnavailable)

        let noCredentialResult = try await unready.liveResponsesWebSearchResponse(
            context: responsesContext(
                try liveResponsesSearchContext(fixture: fixture, native: true),
                providerCredential: nil
            )
        )
        // No saved credential no longer blocks the turn: the anonymous
        // request reaches the transport, which has no scripted response.
        #expect(noCredentialResult.status == .badGateway)

        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await unready.executeResponsesLiveModelHead(
                body: Data("{}".utf8),
                attempt: 0,
                context: context
            )
        }

        let failed = coverageResponder(
            fixture: fixture,
            transport: FailingGatewayTransport(error: .privateFailure)
        )
        let failedResult = try await failed.liveResponsesWebSearchResponse(context: context)
        #expect(failedResult.status == .badGateway)

        let cancelled = coverageResponder(
            fixture: fixture,
            transport: CancellingGatewayTransport()
        )
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.liveResponsesWebSearchResponse(context: context)
        }
    }

}
