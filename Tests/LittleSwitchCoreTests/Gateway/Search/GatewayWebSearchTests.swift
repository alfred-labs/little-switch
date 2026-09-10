import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

// The direct-search loop, its version-bridging case, and their shared gateway
// fixtures stay together as one behavioral suite.
// swiftlint:disable file_length

extension GatewayTests {
    @Test("Eligible streaming without a tool call returns complete native SSE")
    func webSearchStreamingWithoutCall() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "No search needed"]],
                    stopReason: "end_turn",
                    inputTokens: 4,
                    outputTokens: 3
                )
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let request =
            #"{"model":"claude-opus-5","stream":true,"messages":[{"role":"user","content":"hello"}],"#
            + #""tools":[{"type":"web_search_20250305","max_uses":2}]}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )

            #expect(result.status == .ok)
            #expect(result.headers[.contentType] == "text/event-stream")
            let stream = String(buffer: result.body)
            #expect(stream.contains("event: message_start\n"))
            #expect(stream.contains("event: message_stop\n"))
            #expect(stream.contains("claude-opus-5"))
            // The raw upstream model id must not surface as the model field;
            // a provider/model slug may legitimately contain it as a
            // substring.
            #expect(!stream.contains(#""model":"glm-5.2""#))

            let requests = await transport.requests
            #expect(requests.count == 1)
            let upstream = try anthropicObject(requests[0].body)
            #expect(upstream["model"] as? String == "glm-5.2")
            #expect(upstream["stream"] as? Bool == true)
            let tools = try #require(upstream["tools"] as? [[String: Any]])
            #expect(tools.map { $0["name"] as? String } == ["web_search"])
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            #expect(await fixture.state.sessionRequestCount == 1)
        }
    }

    @Test("One search interleaves provider, Firecrawl, and provider requests")
    func singleWebSearch() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "PROVIDER-LEAKME/id?search",
                    content: [
                        [
                            "type": "tool_use",
                            "id": "tool_search",
                            "name": "web_search",
                            "input": ["query": "Swift 6.2 release"],
                        ]
                    ],
                    stopReason: "tool_use",
                    inputTokens: 5,
                    outputTokens: 2
                )
            ),
            response(
                status: .ok,
                body:
                    #"{"success":true,"data":{"web":[{"title":"Swift.org","#
                    + #""url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Swift is current."]],
                    stopReason: "end_turn",
                    inputTokens: 8,
                    outputTokens: 4
                )
            ),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .ok)
            let responseObject = try anthropicObject(data(result.body))
            #expect(responseObject["model"] as? String == "claude-opus-5")
            let content = try #require(responseObject["content"] as? [[String: Any]])
            #expect(
                content.map { $0["type"] as? String }
                    == ["server_tool_use", "web_search_tool_result", "text"]
            )
            try #require(content.count == 3)
            let serverToolID = try #require(content[0]["id"] as? String)
            #expect(isNativeServerToolID(serverToolID))
            #expect(!serverToolID.contains("PROVIDER"))
            #expect(content[1]["tool_use_id"] as? String == serverToolID)

            let requests = await transport.requests
            #expect(
                requests.map(\.url) == [
                    "https://api.z.ai/api/anthropic/v1/messages",
                    "https://api.firecrawl.dev/v2/search",
                    "https://api.z.ai/api/anthropic/v1/messages",
                ]
            )
            try #require(requests.count == 3)
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            #expect(requests[1].headers["authorization"] == ["Bearer firecrawl-secret"])
            #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
            let followUp = try anthropicObject(requests[2].body)
            let messages = try #require(followUp["messages"] as? [[String: Any]])
            #expect(messages.count == 3)
            let toolResult = try #require(messages.last?["content"] as? [[String: Any]])
            #expect((toolResult[0]["content"] as? String)?.contains("Title: Swift.org") == true)
            #expect(await fixture.state.sessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
        #expect(
            event.upstreamExchanges.allSatisfy {
                header("authorization", in: $0.request?.headers ?? []) == TrafficRedactor.mask
            }
        )
    }

    @Test("A dynamic-filtering tool version runs the same direct search loop")
    func dynamicFilteringToolVersion() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "tool_search", query: "Swift 6.2 release")],
                    stopReason: "tool_use"
                )
            ),
            response(
                status: .ok,
                body:
                    #"{"success":true,"data":{"web":[{"title":"Swift.org","#
                    + #""url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Swift is current."]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        // The tool Claude sends after upgrading: a version whose callers
        // default to code execution, which this bridge answers directly.
        let request =
            #"{"model":"claude-opus-5","messages":[{"role":"user","content":"latest Swift"}],"#
            + #""tools":[{"type":"web_search_20260318","name":"web_search","#
            + #""allowed_callers":["code_execution_20260120"],"#
            + #""response_inclusion":"excluded"}]}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )

            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            let content = try #require(object["content"] as? [[String: Any]])
            #expect(
                content.map { $0["type"] as? String }
                    == ["server_tool_use", "web_search_tool_result", "text"]
            )
            try #require(content.count == 3)
            #expect(content[0]["caller"] as? [String: String] == ["type": "direct"])
            #expect(content[1]["caller"] as? [String: String] == ["type": "direct"])

            let requests = await transport.requests
            #expect(
                requests.map(\.url) == [
                    "https://api.z.ai/api/anthropic/v1/messages",
                    "https://api.firecrawl.dev/v2/search",
                    "https://api.z.ai/api/anthropic/v1/messages",
                ]
            )
            try #require(requests.count == 3)
            let upstream = try anthropicObject(requests[0].body)
            let tools = try #require(upstream["tools"] as? [[String: Any]])
            #expect(tools.map { $0["name"] as? String } == ["web_search"])
        }
    }

    @Test("Incoming and configured limits cap Firecrawl and preserve final ordinary tools")
    func webSearchLimit() async throws {
        let fixture = try makeWebSearchFixture(maximumUses: 2)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_one",
                    content: [searchToolBlock(id: "search_one", query: "first")],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_two",
                    content: [
                        searchToolBlock(id: "search_two", query: "second"),
                        [
                            "type": "tool_use",
                            "id": "weather_ignored",
                            "name": "weather",
                            "input": ["city": "Paris"],
                        ],
                    ],
                    stopReason: "tool_use"
                )
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [
                        [
                            "type": "tool_use",
                            "id": "weather_final",
                            "name": "weather",
                            "input": ["city": "Paris"],
                        ]
                    ],
                    stopReason: "tool_use"
                )
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 1))
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            let content = try #require(object["content"] as? [[String: Any]])
            #expect(
                content.map { $0["type"] as? String }
                    == [
                        "server_tool_use",
                        "web_search_tool_result",
                        "server_tool_use",
                        "web_search_tool_result",
                        "tool_use",
                    ]
            )
            try #require(content.count == 5)
            let error = try #require(content[3]["content"] as? [String: String])
            #expect(error["error_code"] == "max_uses_exceeded")
            #expect(content.last?["name"] as? String == "weather")

            let requests = await transport.requests
            #expect(requests.filter { $0.url.contains("firecrawl") }.count == 1)
            try #require(requests.count == 4)
            let finalRequest = try anthropicObject(requests[3].body)
            let tools = try #require(finalRequest["tools"] as? [[String: Any]])
            #expect(tools.map { $0["name"] as? String } == ["weather"])
        }
    }

    @Test("Firecrawl errors become safe search errors followed by one final model call")
    func webSearchFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [
                        ["type": "text", "text": "I will try the search."],
                        searchToolBlock(id: "search", query: "Swift"),
                    ],
                    stopReason: "tool_use"
                )
            ),
            response(status: .tooManyRequests, body: #"{"private":"body"}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Search unavailable"]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            let content = try #require(object["content"] as? [[String: Any]])
            #expect(content.first?["text"] as? String == "I will try the search.")
            let errorBlock = try #require(
                content.first { $0["type"] as? String == "web_search_tool_result" }
            )
            let error = try #require(errorBlock["content"] as? [String: String])
            #expect(error["error_code"] == "unavailable")
            let requests = await transport.requests
            try #require(requests.count == 3)
            let finalRequest = try anthropicObject(requests[2].body)
            let tools = try #require(finalRequest["tools"] as? [[String: Any]])
            #expect(tools.map { $0["name"] as? String } == ["weather"])
        }
    }

    @Test("An empty query skips Firecrawl and returns native invalid_tool_input")
    func invalidWebSearchQuery() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "  ")],
                    stopReason: "tool_use"
                )
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Invalid query"]],
                    stopReason: "end_turn"
                )
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            let content = try #require(object["content"] as? [[String: Any]])
            try #require(content.count >= 2)
            let error = try #require(content[1]["content"] as? [String: String])
            #expect(error["error_code"] == "invalid_tool_input")
            let requests = await transport.requests
            #expect(requests.count == 2)
            #expect(requests.allSatisfy { !$0.url.contains("firecrawl") })
        }
    }

    @Test("A provider failure after search returns a safe gateway error")
    func providerFailureAfterWebSearch() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "Swift")],
                    stopReason: "tool_use"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .internalServerError, body: #"{"private":"provider body"}"#),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .badGateway)
            let text = String(buffer: result.body)
            #expect(text.contains("Provider follow-up failed"))
            #expect(!text.contains("provider body"))
            #expect(await transport.requests.count == 3)
        }
    }

    @Test("The first provider non-success response remains transparent")
    func firstProviderFailureIsTransparent() async throws {
        let fixture = try makeWebSearchFixture()
        let body = #"{"error":"provider-limit"}"#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .tooManyRequests, body: body)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status.code == 429)
            #expect(String(buffer: result.body) == body)
            #expect(await fixture.state.sessionRequestCount == 1)
        }
    }

    @Test("Cancellation during Firecrawl propagates through the gateway lifecycle")
    func webSearchCancellation() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = CancellingFirecrawlGatewayTransport(
            firstResponse: response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "Swift")],
                    stopReason: "tool_use"
                )
            )
        )
        let recorder = TrafficTestRecorder()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .internalServerError)
        }
        #expect(await transport.requestCount == 2)
        #expect(await fixture.state.sessionRequestCount == 1)
        #expect(recorder.events.first?.lifecycle == .cancelled)
    }

}

private actor CancellingFirecrawlGatewayTransport: UpstreamTransport {
    private let firstResponse: HTTPClientResponse
    private(set) var requestCount = 0

    init(firstResponse: HTTPClientResponse) {
        self.firstResponse = firstResponse
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if let body = request.body {
            for try await _ in body {}
        }
        requestCount += 1
        if requestCount == 1 {
            return firstResponse
        }
        throw CancellationError()
    }
}

func webSearchRequest(streaming: Bool, maximumUses: Int) -> String {
    #"{"model":"claude-opus-5","stream":\#(streaming),"#
        + #""messages":[{"role":"user","content":"latest Swift"}],"#
        + #""tools":[{"type":"web_search_20250305","max_uses":\#(maximumUses)},"#
        + #"{"name":"weather","input_schema":{"type":"object"}}]}"#
}

func searchToolBlock(id: String, query: String) -> [String: Any] {
    [
        "type": "tool_use",
        "id": id,
        "name": "web_search",
        "input": ["query": query],
    ]
}

func anthropicModelResponse(
    id: String,
    content: [[String: Any]],
    stopReason: String,
    inputTokens: Int = 1,
    outputTokens: Int = 1
) -> String {
    let object: [String: Any] = [
        "id": id,
        "type": "message",
        "role": "assistant",
        "model": "glm-5.2",
        "content": content,
        "stop_reason": stopReason,
        "stop_sequence": NSNull(),
        "usage": ["input_tokens": inputTokens, "output_tokens": outputTokens],
    ]
    let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

func anthropicObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
