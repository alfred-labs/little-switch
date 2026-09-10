import AsyncHTTPClient
import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic live search outcome coverage")
struct GatewaySearchOutcomeCoverageTests {
    @Test("Empty live search queries force a safe final turn")
    func invalidQuery() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            modelSearchResponse(id: "msg_empty", query: "  \n"),
            modelFinalResponse(id: "msg_after_empty"),
        ])
        let stream = try await liveBody(fixture: fixture, transport: transport)
        #expect(stream.contains("invalid_tool_input"))
        #expect(await transport.requests.count == 2)
    }

    @Test("The live search maximum is enforced after one successful use")
    func maximumUses() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture(maximumUses: 1)
        let transport = RecordingGatewayTransport(responses: [
            modelSearchResponse(id: "msg_first", query: "Swift"),
            response(status: .ok, body: firecrawlSuccess),
            modelSearchResponse(id: "msg_second", query: "Swift again"),
            modelFinalResponse(id: "msg_after_max"),
        ])
        let stream = try await liveBody(
            fixture: fixture,
            transport: transport,
            maximumUses: 1
        )
        #expect(stream.contains("max_uses_exceeded"))
        #expect(await transport.requests.count == 4)
    }

    @Test("A Firecrawl failure becomes a private unavailable result")
    func unavailable() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            modelSearchResponse(id: "msg_search", query: "Swift"),
            response(status: .internalServerError, body: #"{"private":"failure"}"#),
            modelFinalResponse(id: "msg_after_failure"),
        ])
        let stream = try await liveBody(fixture: fixture, transport: transport)
        #expect(stream.contains("unavailable"))
        #expect(!stream.contains("private"))
    }

    @Test("Firecrawl cancellation remains cancellation")
    func cancellation() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let context = try liveContext(fixture: fixture)
        let transport = SteppingGatewayTransport(steps: [
            .response(modelSearchResponse(id: "msg_search", query: "Swift")),
            .cancellation,
        ])
        let responder = coverageResponder(fixture: fixture, transport: transport)
        let response = try await responder.liveWebSearchResponse(
            context: context,
            searchCredential: "firecrawl-secret"
        )
        await #expect(throws: CancellationError.self) {
            _ = try await responseBodyData(response.body)
        }
    }

    private func liveBody(
        fixture: GatewayFixture,
        transport: RecordingGatewayTransport,
        maximumUses: Int = 2
    ) async throws -> String {
        let responder = coverageResponder(fixture: fixture, transport: transport)
        let response = try await responder.liveWebSearchResponse(
            context: liveContext(fixture: fixture, maximumUses: maximumUses),
            searchCredential: "firecrawl-secret"
        )
        return String(bytes: try await responseBodyData(response.body), encoding: .utf8) ?? ""
    }

    private func liveContext(
        fixture: GatewayFixture,
        maximumUses: Int = 2
    ) throws -> GatewayWebSearchContext {
        let base = try GatewayTests().gatewayLiveContext(fixture: fixture)
        return GatewayWebSearchContext(
            prepared: PreparedWebSearchRequest(
                upstreamBody: base.prepared.upstreamBody,
                originalModel: base.prepared.originalModel,
                streaming: true,
                maximumUses: maximumUses,
                searchOptions: base.prepared.searchOptions
            ),
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: UUID()
        )
    }
}

private func modelSearchResponse(id: String, query: String) -> HTTPClientResponse {
    response(
        status: .ok,
        body: anthropicModelResponse(
            id: id,
            content: [searchToolBlock(id: "search_\(id)", query: query)],
            stopReason: "tool_use"
        )
    )
}

private func modelFinalResponse(id: String) -> HTTPClientResponse {
    response(
        status: .ok,
        body: anthropicModelResponse(
            id: id,
            content: [["type": "text", "text": "done"]],
            stopReason: "end_turn"
        )
    )
}

private let firecrawlSuccess =
    #"{"success":true,"data":{"web":[{"title":"Swift","url":"https://swift.org","description":"Swift"}]}}"#
