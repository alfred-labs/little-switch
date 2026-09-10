import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Gateway generated model request bounds")
struct GatewayGeneratedRequestBoundsTests {
    private let maximumRequestBytes = 4 * 1_024

    @Test("Buffered Anthropic rejects an oversized Firecrawl follow-up before transport")
    func bufferedAnthropicFollowUp() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let request = webSearchRequest(streaming: false, maximumUses: 2)
        #expect(Data(request.utf8).count < maximumRequestBytes)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "Swift")],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: try oversizedFirecrawlResponse()),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "must not be reached"]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let app = GatewayTests().makeApplication(
            fixture: fixture,
            transport: transport,
            maximumRequestBytes: maximumRequestBytes
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )

            #expect(result.status == .badGateway)
            let body = String(buffer: result.body)
            #expect(body.contains("Provider request failed"))
            #expect(!body.contains("must not be reached"))
        }

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.body.count ?? .max < maximumRequestBytes)
        #expect(requests.map(\.url).filter { !$0.contains("firecrawl") }.count == 1)
    }

    @Test("Buffered Responses rejects an oversized Firecrawl follow-up before transport")
    func bufferedResponsesFollowUp() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let slug = try responsesSlug(fixture)
        let request = responsesWebSearchRequest(slug: slug, streaming: false)
        #expect(Data(request.utf8).count < maximumRequestBytes)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search",
                    callID: "call_search",
                    query: "Swift"
                )
            ),
            response(status: .ok, body: try oversizedFirecrawlResponse()),
            response(status: .ok, body: responsesFinalResponse("must not be reached")),
        ])
        let app = GatewayTests().makeApplication(
            fixture: fixture,
            transport: transport,
            maximumRequestBytes: maximumRequestBytes
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )

            #expect(result.status == .badGateway)
            let body = String(buffer: result.body)
            #expect(body.contains("Provider request failed"))
            #expect(!body.contains("must not be reached"))
        }

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.body.count ?? .max < maximumRequestBytes)
        #expect(requests.map(\.url).filter { !$0.contains("firecrawl") }.count == 1)
    }

    @Test("Live Anthropic emits a safe terminal when the Firecrawl follow-up is oversized")
    func liveAnthropicFollowUp() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let context = try GatewayTests().gatewayLiveContext(fixture: fixture)
        #expect(context.prepared.upstreamBody.count < maximumRequestBytes)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "Swift")],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: try oversizedFirecrawlResponse()),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "must not be reached"]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: maximumRequestBytes,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(context: context)
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(ObservingResponseBodyWriter(recorder: recorder))
        }

        let stream = await recorder.bodyString
        #expect(stream.components(separatedBy: "event: error\n").count - 1 == 1)
        #expect(stream.contains("Internal server error"))
        #expect(!stream.contains("must not be reached"))
        #expect(!stream.contains("maximumRequestBytes"))
        #expect(!stream.contains("event: message_stop\n"))
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.body.count ?? .max < maximumRequestBytes)
        #expect(requests.map(\.url).filter { !$0.contains("firecrawl") }.count == 1)
    }

    @Test("Live Responses emits a safe terminal when the Firecrawl follow-up is oversized")
    func liveResponsesFollowUp() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)
        #expect(context.prepared.upstreamBody.count < maximumRequestBytes)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search",
                    callID: "call_search",
                    query: "Swift"
                )
            ),
            response(status: .ok, body: try oversizedFirecrawlResponse()),
            response(status: .ok, body: responsesFinalResponse("must not be reached")),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: maximumRequestBytes,
            requiredAuthorityPort: nil
        )

        let response = try await responder.responsesWebSearchResponse(context: context)
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(ObservingResponseBodyWriter(recorder: recorder))
        }

        let events = try ResponsesStreamingTestSupport.events(await recorder.body)
        #expect(events.filter { $0.name == "error" }.count == 1)
        #expect(events.filter { $0.name == "response.failed" }.count == 1)
        #expect(!events.contains { $0.name == "response.completed" })
        let stream = await recorder.bodyString
        #expect(stream.contains("Internal server error"))
        #expect(!stream.contains("must not be reached"))
        #expect(!stream.contains("maximumRequestBytes"))
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.body.count ?? .max < maximumRequestBytes)
        #expect(requests.map(\.url).filter { !$0.contains("firecrawl") }.count == 1)
    }
}

private func oversizedFirecrawlResponse() throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "success": true,
            "data": [
                "web": [
                    [
                        "title": "Swift.org",
                        "url": "https://swift.org/",
                        "description": String(repeating: "bounded-result-", count: 1_024),
                    ]
                ]
            ],
        ],
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return try #require(String(data: data, encoding: .utf8))
}
