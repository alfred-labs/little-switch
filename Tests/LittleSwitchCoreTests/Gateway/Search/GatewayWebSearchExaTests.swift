import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Anthropic searches use Exa and retain native results", arguments: [false, true])
    func anthropicSearchWithExa(streaming: Bool) async throws {
        let fixture = try makeWebSearchFixture(provider: .exa)
        let transport = exaGatewayTransport(responses: false)
        let app = makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: streaming, maximumUses: 2))
            )
            #expect(result.status == .ok)
            if streaming {
                let body = String(buffer: result.body)
                #expect(body.contains("event: message_stop"))
                #expect(body.contains("web_search_tool_result"))
                #expect(body.contains("https://swift.org/"))
            } else {
                let object = try anthropicObject(data(result.body))
                let content = try #require(object["content"] as? [[String: Any]])
                #expect(
                    content.compactMap { $0["type"] as? String } == [
                        "server_tool_use", "web_search_tool_result", "text",
                    ])
                let hits = try #require(content[1]["content"] as? [[String: Any]])
                #expect(hits.first?["url"] as? String == "https://swift.org/")
            }
        }
        try await assertExaGatewayRequests(transport, responses: false)
        #expect(await fixture.state.sessionRequestCount == 1)
    }

    @Test("Responses searches use Exa with public search lifecycle", arguments: [false, true])
    func responsesSearchWithExa(streaming: Bool) async throws {
        let fixture = try await makeResponsesWebSearchFixture(provider: .exa)
        let transport = exaGatewayTransport(responses: true)
        let app = makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug, streaming: streaming))
            )
            #expect(result.status == .ok)
            if streaming {
                let body = String(buffer: result.body)
                #expect(body.contains("event: response.completed"))
                #expect(body.contains("web_search_call"))
                #expect(body.contains("https://swift.org/"))
            } else {
                let object = try responsesGatewayObject(data(result.body))
                let output = try #require(object["output"] as? [[String: Any]])
                #expect(output.compactMap { $0["type"] as? String } == ["web_search_call", "message"])
                try assertGatewayResponsesSearchItem(
                    #require(output.first),
                    query: "Swift release",
                    sources: ["https://swift.org/"])
            }
        }
        try await assertExaGatewayRequests(transport, responses: true)
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    @Test("Desktop managed search returns Exa highlights as snippets")
    func managedSearchWithExa() async throws {
        let fixture = try makeWebSearchFixture(provider: .exa)
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: exaGatewaySearchBody)])
        let app = makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"Swift release"}"#)
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body)) as NSDictionary
            #expect(
                object == [
                    "results": [
                        [
                            "title": "Swift.org", "url": "https://swift.org/",
                            "snippet": "Swift documentation\nRelease notes",
                        ]
                    ]
                ] as NSDictionary)
        }
        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.exa.ai/search")
        #expect(request.headers["x-api-key"] == ["exa-secret"])
    }
}

private let exaGatewaySearchBody =
    #"{"results":[{"title":"Swift.org","url":"https://swift.org/","highlights":["Swift documentation","Release notes"]}]}"#

private func exaGatewayTransport(responses: Bool) -> RecordingGatewayTransport {
    let first: String
    let last: String
    if responses {
        first = responsesModelResponse(
            id: "response_search",
            output: [
                [
                    "id": "fc_search", "type": "function_call", "status": "completed",
                    "name": "web_search", "call_id": "call_search", "arguments": #"{"query":"Swift release"}"#,
                ]
            ])
        last = responsesModelResponse(
            id: "response_final",
            output: [
                [
                    "type": "message", "role": "assistant",
                    "content": [["type": "output_text", "text": "Swift is current."]],
                ]
            ])
    } else {
        first = anthropicModelResponse(
            id: "message_search",
            content: [
                searchToolBlock(
                    id: "tool_search",
                    query: "Swift release")
            ],
            stopReason: "tool_use"
        )
        last = anthropicModelResponse(
            id: "message_final",
            content: [["type": "text", "text": "Swift is current."]],
            stopReason: "end_turn"
        )
    }
    return RecordingGatewayTransport(responses: [
        response(status: .ok, body: first), response(status: .ok, body: exaGatewaySearchBody),
        response(status: .ok, body: last),
    ])
}

private func assertExaGatewayRequests(_ transport: RecordingGatewayTransport, responses: Bool) async throws {
    let requests = await transport.requests
    try #require(requests.count == 3)
    let modelURL =
        responses
        ? "https://api.z.ai/api/coding/paas/v4/chat/completions" : "https://api.z.ai/api/anthropic/v1/messages"
    #expect(requests.map(\.url) == [modelURL, "https://api.exa.ai/search", modelURL])
    #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
    #expect(requests[1].headers["x-api-key"] == ["exa-secret"])
    #expect(requests[1].headers["authorization"].isEmpty)
    #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
    #expect(requests[0].headers["x-api-key"].isEmpty)
    #expect(requests[2].headers["x-api-key"].isEmpty)
    let search = try anthropicObject(requests[1].body)
    #expect(search["query"] as? String == "Swift release")
    #expect(search["numResults"] as? Int == 10)
    let followUp = try anthropicObject(requests[2].body)
    let messages = try #require(followUp["messages"] as? [[String: Any]])
    let content: String?
    if responses {
        #expect(messages.last?["role"] as? String == "tool")
        content = messages.last?["content"] as? String
    } else {
        let blocks = try #require(messages.last?["content"] as? [[String: Any]])
        content = blocks.first?["content"] as? String
    }
    #expect(content?.contains("Title: Swift.org") == true)
    #expect(content?.contains("Swift documentation\nRelease notes") == true)
}
