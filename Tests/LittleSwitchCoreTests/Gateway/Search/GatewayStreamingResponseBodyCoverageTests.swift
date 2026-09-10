import Foundation
import Hummingbird
import Testing

@testable import LittleSwitchCore

@Suite("Gateway streaming response body coverage")
struct GatewayResponseBodyCoverageTests {
    @Test("Live response bodies preserve cancellation and map failed client writes")
    func clientWriteFailures() async throws {
        try await anthropicClientWriteFailures()
        try await responsesClientWriteFailures()
        try await chatClientWriteFailures()
    }

    @Test("Chat JSON streaming rejects cumulative bytes above the configured bound")
    func oversizedChatJSON() async throws {
        let fixture = try GatewayTests().makeFixture()
        let upstream = coverageResponse(
            DemandTrackedBodySequence(chunks: [Data("12345".utf8), Data("67890".utf8)]),
            contentType: "application/json"
        )
        let responder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [upstream]),
            maximumErrorBytes: 8
        )
        let response = try await responder.chatCompletionsResponsesResponse(
            gatewayLiveChatContext(fixture: fixture, includeTools: false)
        )
        #expect(response.status == .badGateway)
        let publicBody = try await responseBodyData(response.body)
        #expect(try !#require(String(bytes: publicBody, encoding: .utf8)).contains("12345"))
    }

    @Test("Adapted Responses requests remain bounded after conversion")
    func adaptedRequestBounds() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)
        let body = Data(#"{"model":"public","input":"x"}"#.utf8)
        let liveAdapted = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: context.target.model.id,
            mode: .streaming(toolStream: true)
        )
        let bufferedAdapted = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: context.target.model.id,
            mode: .buffered
        )
        try #require(liveAdapted.upstreamBody.count > body.count)
        try #require(bufferedAdapted.upstreamBody.count > body.count)

        let liveResponder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            maximumRequestBytes: body.count
        )
        await #expect(throws: GatewayResponsesLiveError.self) {
            _ = try await liveResponder.executeResponsesLiveModelHead(
                body: body,
                attempt: 0,
                context: context
            )
        }

        let bufferedPrepared = PreparedResponsesWebSearchRequest(
            upstreamBody: body,
            originalBody: context.prepared.originalBody,
            originalModel: context.prepared.originalModel,
            originalToolsJSON: context.prepared.originalToolsJSON,
            originalInputJSON: context.prepared.originalInputJSON,
            streaming: false,
            maximumUses: context.prepared.maximumUses,
            searchOptions: context.prepared.searchOptions
        )
        let bufferedContext = GatewayResponsesWebSearchContext(
            prepared: bufferedPrepared,
            configuration: context.configuration,
            target: context.target,
            providerCredential: context.providerCredential,
            searchCredential: context.searchCredential,
            incomingHeaders: context.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: true
        )
        let bufferedResponder = coverageResponder(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            maximumRequestBytes: body.count
        )
        let response = try await bufferedResponder.responsesWebSearchResponse(
            context: bufferedContext
        )
        #expect(response.status == .badGateway)
    }

    private func anthropicClientWriteFailures() async throws {
        let tests = GatewayTests()
        let fixture = try tests.makeWebSearchFixture()
        let context = try tests.gatewayLiveContext(fixture: fixture)
        let providerBody = anthropicModelResponse(
            id: "msg_writer",
            content: [["type": "text", "text": "writer"]],
            stopReason: "end_turn"
        )
        for failure in [CoverageWriterFailure.cancellation, .error] {
            let responder = coverageResponder(
                fixture: fixture,
                transport: RecordingGatewayTransport(responses: [
                    response(status: .ok, body: providerBody)
                ])
            )
            let response = try await responder.liveWebSearchResponse(
                context: context,
                searchCredential: nil
            )
            if failure == .cancellation {
                await #expect(throws: CancellationError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            } else {
                await #expect(throws: GatewayAnthropicLiveError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            }
        }
    }

    private func responsesClientWriteFailures() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture, native: true)
        let providerBody = try responseData(
            responseObject(
                id: "resp_writer",
                createdAt: 1,
                status: "completed",
                output: [],
                usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
            )
        )
        for failure in [CoverageWriterFailure.cancellation, .error] {
            let responder = coverageResponder(
                fixture: fixture,
                transport: RecordingGatewayTransport(responses: [
                    coverageBytesResponse(providerBody, contentType: "application/json")
                ])
            )
            let response = try await responder.liveResponsesWebSearchResponse(context: context)
            if failure == .cancellation {
                await #expect(throws: CancellationError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            } else {
                await #expect(throws: GatewayResponsesLiveError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            }
        }
    }

    private func chatClientWriteFailures() async throws {
        let fixture = try GatewayTests().makeFixture()
        let context = try gatewayLiveChatContext(fixture: fixture, includeTools: false)
        for failure in [CoverageWriterFailure.cancellation, .error] {
            let responder = coverageResponder(
                fixture: fixture,
                transport: RecordingGatewayTransport(responses: [
                    response(status: .ok, body: responsesFinalResponse("writer"))
                ])
            )
            let response = try await responder.chatCompletionsResponsesResponse(context)
            if failure == .cancellation {
                await #expect(throws: CancellationError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            } else {
                do {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                    Issue.record("Expected the failed client write to propagate")
                } catch {
                    #expect(String(describing: error).contains("clientWriteFailed"))
                }
            }
        }
    }
}
