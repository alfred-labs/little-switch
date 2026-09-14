import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Eligible streaming without a search call returns complete live SSE")
    func responsesWebSearchStreamingWithoutCall() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: responsesFinalResponse("No search needed"))
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug, streaming: true))
            )
            #expect(result.status == .ok)
            #expect(result.headers[.contentType] == "text/event-stream")
            let stream = String(buffer: result.body)
            #expect(stream.contains("event: response.created\n"))
            #expect(stream.contains("event: response.completed\n"))
            #expect(stream.contains(slug))
            #expect(!stream.contains(#""""model":"glm-5.2""""#))
        }

        let requests = await transport.requests
        try #require(requests.count == 1)
        let upstream = try responsesGatewayObject(requests[0].body)
        #expect(upstream["stream"] as? Bool == true)
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    @Test("Configured search limit forces one final provider turn")
    func responsesWebSearchLimit() async throws {
        let fixture = try await makeResponsesWebSearchFixture(maximumUses: 3)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: responsesSearchResponse(id: "resp_one", callID: "call_one", query: "first")),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .ok, body: responsesSearchResponse(id: "resp_two", callID: "call_two", query: "second")),
            response(status: .ok, body: responsesFinalResponse("Search limit reached")),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(
                    string: responsesWebSearchRequest(slug: slug, maxToolCalls: 1)
                )
            )
            #expect(result.status == .ok)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(output.compactMap { $0["type"] as? String } == ["web_search_call", "web_search_call", "message"])
            try #require(output.count == 3)
            try assertGatewayResponsesSearchItem(output[0], query: "first")
            try assertGatewayResponsesSearchItem(output[1], query: "second", failed: true)
        }

        let requests = await transport.requests
        #expect(requests.filter { $0.url.contains("firecrawl") }.count == 1)
        try #require(requests.count == 4)
        let finalRequest = try responsesGatewayObject(requests[3].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "max_uses_exceeded")
        let tools = try #require(finalRequest["tools"] as? [[String: Any]])
        #expect(
            tools.compactMap {
                ($0["function"] as? [String: Any])?["name"] as? String
            } == ["weather"]
        )
    }

    @Test("An empty search query skips Firecrawl and forces a safe final turn")
    func responsesWebSearchEmptyQuery() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: responsesSearchResponse(id: "resp_search", callID: "call_search", query: "  ")),
            response(status: .ok, body: responsesFinalResponse("Invalid query")),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            try assertGatewayResponsesSearchItem(#require(output.first), query: "  ", failed: true)
        }

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { !$0.url.contains("firecrawl") })
        let finalRequest = try responsesGatewayObject(requests[1].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "invalid_request")
    }

    @Test("Firecrawl failure becomes unavailable without leaking its body")
    func responsesWebSearchFirecrawlFailure() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok, body: responsesSearchResponse(id: "resp_search", callID: "call_search", query: "Swift")),
            response(status: .tooManyRequests, body: #"{"private":"firecrawl body"}"#),
            response(status: .ok, body: responsesFinalResponse("Search unavailable")),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
            #expect(!String(buffer: result.body).contains("firecrawl body"))
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            try assertGatewayResponsesSearchItem(#require(output.first), query: "Swift", failed: true)
        }

        let requests = await transport.requests
        try #require(requests.count == 3)
        let finalRequest = try responsesGatewayObject(requests[2].body)
        let messages = try #require(finalRequest["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "unavailable")
    }

    @Test("The first provider failure remains transparent")
    func responsesFirstProviderFailure() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let providerBody = #"{"error":"provider-limit"}"#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .tooManyRequests, body: providerBody)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status.code == 429)
            #expect(String(buffer: result.body) == providerBody)
        }
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    @Test("A provider follow-up failure returns a safe gateway error")
    func responsesProviderFollowUpFailure() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok, body: responsesSearchResponse(id: "resp_search", callID: "call_search", query: "Swift")),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .internalServerError, body: #"{"private":"provider body"}"#),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .badGateway)
            let text = String(buffer: result.body)
            #expect(text.contains("Provider follow-up failed"))
            #expect(!text.contains("provider body"))
        }
    }

    @Test("Invalid successful provider output returns a safe gateway error")
    func responsesInvalidProviderOutput() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: "{}")])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .badGateway)
            #expect(String(buffer: result.body).contains("Invalid provider response"))
        }
    }
}

func assertGatewayResponsesSearchItem(
    _ item: [String: Any],
    query: String,
    sources: [String] = [],
    failed: Bool = false
) throws {
    let id = try #require(item["id"] as? String)
    #expect(!id.isEmpty)
    var action: [String: Any] = ["type": "search", "query": query]
    if !sources.isEmpty {
        action["sources"] = sources.map { ["type": "url", "url": $0] }
    }
    let expected: [String: Any] = [
        "id": id,
        "type": "web_search_call",
        "status": failed ? "failed" : "completed",
        "action": action,
    ]
    #expect(NSDictionary(dictionary: item).isEqual(to: expected))
}

func responsesSlug(_ fixture: GatewayFixture) throws -> String {
    let mapping = try #require(
        fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
    )
    return CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
}

func responsesSearchResponse(
    id: String,
    callID: String,
    query: String
) -> String {
    responsesModelResponse(
        id: id,
        output: [
            [
                "id": "fc_\(callID)",
                "type": "function_call",
                "status": "completed",
                "name": "web_search",
                "call_id": callID,
                "arguments": #"{"query":"\#(query)"}"#,
            ]
        ]
    )
}

func responsesFinalResponse(_ text: String) -> String {
    responsesModelResponse(
        id: "resp_final",
        output: [
            [
                "id": "msg_final",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": text,
                        "annotations": [],
                        "logprobs": [],
                    ]
                ],
            ]
        ]
    )
}
