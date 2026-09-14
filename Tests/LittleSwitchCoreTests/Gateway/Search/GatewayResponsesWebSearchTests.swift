import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Codex web search interleaves provider, Firecrawl, and provider requests")
    func responsesWebSearch() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = responsesSearchTransport()
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let requestBody =
            #"""
            {
              "model": "\#(slug)",
              "input": "latest Swift",
              "stream": false,
              "tools": [
                {
                  "type": "web_search",
                  "filters": {
                    "allowed_domains": ["swift.org"],
                    "blocked_domains": ["example.com"]
                  },
                  "user_location": {
                    "type": "approximate",
                    "city": "Paris",
                    "region": "Ile-de-France",
                    "country": "FR"
                  }
                },
                {"type": "function", "name": "weather", "parameters": {"type": "object"}}
              ]
            }
            """#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: requestBody)
            )

            #expect(result.status == .ok)
            #expect(result.headers[.contentType] == "application/json")
            let object = try responsesGatewayObject(data(result.body))
            #expect(object["model"] as? String == slug)
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(
                output.compactMap { $0["type"] as? String }
                    == ["web_search_call", "message"]
            )
            #expect(output.allSatisfy { $0["name"] as? String != "web_search" })
            try assertGatewayResponsesSearchItem(
                #require(output.first),
                query: "Swift 6.3 release",
                sources: ["https://swift.org/"]
            )
            #expect(await fixture.state.codexSessionRequestCount == 1)
        }

        let requests = await transport.requests
        #expect(
            requests.map(\.url) == [
                "https://api.z.ai/api/coding/paas/v4/chat/completions",
                "https://api.firecrawl.dev/v2/search",
                "https://api.z.ai/api/coding/paas/v4/chat/completions",
            ]
        )
        try #require(requests.count == 3)
        #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
        #expect(requests[1].headers["authorization"] == ["Bearer firecrawl-secret"])
        #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
        let firecrawl = try responsesGatewayObject(requests[1].body)
        #expect(firecrawl["includeDomains"] as? [String] == ["swift.org"])
        #expect(firecrawl["excludeDomains"] as? [String] == ["example.com"])
        #expect(firecrawl["location"] as? String == "Paris, Ile-de-France")
        #expect(firecrawl["country"] as? String == "FR")
        let first = try responsesGatewayObject(requests[0].body)
        #expect(first["model"] as? String == "glm-5.2")
        #expect(first["stream"] as? Bool == false)
        let firstTools = try #require(first["tools"] as? [[String: Any]])
        #expect(
            firstTools.compactMap {
                ($0["function"] as? [String: Any])?["name"] as? String
            } == ["web_search", "weather"]
        )
        let followUp = try responsesGatewayObject(requests[2].body)
        let messages = try #require(followUp["messages"] as? [[String: Any]])
        #expect(messages.last?["role"] as? String == "tool")
        #expect((messages.last?["content"] as? String)?.contains("Title: Swift.org") == true)

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
        #expect(
            event.upstreamExchanges.allSatisfy {
                header("authorization", in: $0.request?.headers ?? []) == TrafficRedactor.mask
            }
        )
    }

    @Test("Codex web search stays off when the request refuses external web access")
    func responsesWebSearchExternalAccessRefused() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesModelResponse(
                    id: "resp_no_search",
                    output: [
                        [
                            "id": "msg_no_search",
                            "type": "message",
                            "status": "completed",
                            "content": [
                                ["type": "output_text", "text": "No search needed."]
                            ],
                        ]
                    ],
                    inputTokens: 5,
                    outputTokens: 4
                )
            )
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let requestBody =
            #"""
            {
              "model": "\#(slug)",
              "input": "latest Swift",
              "stream": false,
              "tools": [{"type": "web_search", "external_web_access": false}]
            }
            """#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: requestBody)
            )

            #expect(result.status == .ok)
            let requests = await transport.requests
            // One model turn, no search turn: the refusal keeps the bridge
            // disengaged, matching the native backend's semantics.
            try #require(requests.count == 1)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(output.map { $0["type"] as? String } == ["message"])
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 1)
    }

    @Test("Codex web search interleaves provider, Tavily, and provider requests")
    func responsesWebSearchWithTavily() async throws {
        let fixture = try await makeResponsesWebSearchFixture(provider: .tavily)
        let transport = responsesSearchTransport(provider: .tavily)
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let requestBody = responsesWebSearchRequest(slug: slug)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: requestBody)
            )

            #expect(result.status == .ok)
            let requests = await transport.requests
            #expect(
                requests.map(\.url) == [
                    "https://api.z.ai/api/coding/paas/v4/chat/completions",
                    "https://api.tavily.com/search",
                    "https://api.z.ai/api/coding/paas/v4/chat/completions",
                ]
            )
            try #require(requests.count == 3)
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            #expect(requests[1].headers["authorization"] == ["Bearer tavily-secret"])
            #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
            let search = try responsesGatewayObject(requests[1].body)
            #expect(search["query"] as? String == "Swift 6.3 release")
            #expect(search["include_domains"] == nil)
            #expect(search["location"] == nil)
            let first = try responsesGatewayObject(requests[0].body)
            #expect(first["model"] as? String == "glm-5.2")
            let followUp = try responsesGatewayObject(requests[2].body)
            let messages = try #require(followUp["messages"] as? [[String: Any]])
            #expect(messages.last?["role"] as? String == "tool")
            #expect((messages.last?["content"] as? String)?.contains("Title: Swift.org") == true)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            try assertGatewayResponsesSearchItem(
                #require(output.first),
                query: "Swift 6.3 release",
                sources: ["https://swift.org/"]
            )
            #expect(await fixture.state.codexSessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
    }

    @Test("Codex web search interleaves provider, Brave, and provider requests")
    func responsesWebSearchWithBrave() async throws {
        let fixture = try await makeResponsesWebSearchFixture(provider: .brave)
        let transport = responsesSearchTransport(provider: .brave)
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let requestBody = responsesWebSearchRequest(slug: slug)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: requestBody)
            )

            #expect(result.status == .ok)
            let requests = await transport.requests
            try #require(requests.count == 3)
            #expect(requests[0].url == "https://api.z.ai/api/coding/paas/v4/chat/completions")
            #expect(
                requests[1].url
                    == "https://api.search.brave.com/res/v1/web/search?q=Swift%206.3%20release&count=10"
            )
            #expect(requests[2].url == "https://api.z.ai/api/coding/paas/v4/chat/completions")
            #expect(requests[0].headers["authorization"] == ["Bearer selected-secret"])
            // Brave's credential rides the subscription header, not a bearer.
            #expect(requests[1].headers["x-subscription-token"] == ["brave-secret"])
            #expect(requests[1].headers["authorization"].isEmpty)
            #expect(requests[2].headers["authorization"] == ["Bearer selected-secret"])
            let searchComponents = try #require(URLComponents(string: requests[1].url))
            #expect(
                searchComponents.queryItems == [
                    URLQueryItem(name: "q", value: "Swift 6.3 release"),
                    URLQueryItem(name: "count", value: "10"),
                ])
            let first = try responsesGatewayObject(requests[0].body)
            #expect(first["model"] as? String == "glm-5.2")
            let followUp = try responsesGatewayObject(requests[2].body)
            let messages = try #require(followUp["messages"] as? [[String: Any]])
            #expect(messages.last?["role"] as? String == "tool")
            #expect((messages.last?["content"] as? String)?.contains("Title: Swift.org") == true)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            try assertGatewayResponsesSearchItem(
                #require(output.first),
                query: "Swift 6.3 release",
                sources: ["https://swift.org/"]
            )
            #expect(await fixture.state.codexSessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
    }

    func makeResponsesWebSearchFixture(
        maximumUses: Int = 3,
        resultsLimit: Int = 10,
        provider: WebSearchProvider = .firecrawl
    ) async throws -> GatewayFixture {
        let base = try makeFixture()
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: base.snapshot.providers,
            mappings: base.snapshot.mappings,
            codex: base.snapshot.codex,
            webSearch: WebSearchConfiguration(
                provider: provider,
                resultsLimit: resultsLimit,
                maximumUses: maximumUses
            )
        )
        try base.secrets.write(
            provider.searchTestCredential,
            account: .webSearch(provider)
        )
        let state = GatewayState(snapshot: snapshot)
        // The save-time probe would have learned this chat-completions-only
        // preset has no native /v1/responses route; the fixture's chat-shaped
        // replay bodies take that learned adapter wire.
        for provider in snapshot.providers where provider.name == "z.ai" {
            await state.responsesCapabilities.record(
                providerID: provider.id,
                supportsNative: false
            )
        }
        return GatewayFixture(
            snapshot: snapshot,
            state: state,
            secrets: base.secrets
        )
    }
}

func responsesModelResponse(
    id: String,
    output: [[String: Any]],
    inputTokens: Int = 1,
    outputTokens: Int = 1
) -> String {
    let text =
        output
        .first { $0["type"] as? String == "message" }
        .flatMap { $0["content"] as? [[String: Any]] }?
        .first { $0["type"] as? String == "output_text" }?["text"] as? String
    let toolCalls = output.compactMap { item -> [String: Any]? in
        guard item["type"] as? String == "function_call",
            let callID = item["call_id"] as? String,
            let name = item["name"] as? String,
            let arguments = item["arguments"] as? String
        else {
            return nil
        }
        return [
            "id": callID,
            "type": "function",
            "function": ["name": name, "arguments": arguments],
        ]
    }
    var message: [String: Any] = [
        "role": "assistant",
        "content": text ?? NSNull(),
    ]
    if !toolCalls.isEmpty {
        message["tool_calls"] = toolCalls
    }
    let object: [String: Any] = [
        "id": id,
        "object": "chat.completion",
        "created": 40,
        "model": "glm-5.2",
        "choices": [
            [
                "index": 0,
                "finish_reason": toolCalls.isEmpty ? "stop" : "tool_calls",
                "message": message,
            ]
        ],
        "usage": [
            "prompt_tokens": inputTokens,
            "completion_tokens": outputTokens,
            "total_tokens": inputTokens + outputTokens,
        ],
    ]
    let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

private func responsesSearchTransport(provider: WebSearchProvider = .firecrawl) -> RecordingGatewayTransport {
    let searchBody = gatewaySearchResponseBody(provider: provider)
    return RecordingGatewayTransport(responses: [
        response(
            status: .ok,
            body: responsesModelResponse(
                id: "resp_search",
                output: [
                    ["id": "rs_1", "type": "reasoning", "summary": []],
                    [
                        "id": "fc_search",
                        "type": "function_call",
                        "status": "completed",
                        "name": "web_search",
                        "call_id": "call_search",
                        "arguments": #"{"query":"Swift 6.3 release"}"#,
                    ],
                ],
                inputTokens: 5,
                outputTokens: 2
            )
        ),
        response(
            status: .ok,
            body: searchBody
        ),
        response(
            status: .ok,
            body: responsesModelResponse(
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
                                "text": "Swift is current.",
                                "annotations": [],
                                "logprobs": [],
                            ]
                        ],
                    ]
                ],
                inputTokens: 8,
                outputTokens: 4
            )
        ),
    ])
}

func responsesGatewayObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func responsesWebSearchRequest(
    slug: String,
    streaming: Bool = false,
    maxToolCalls: Int? = nil
) -> String {
    let maximum = maxToolCalls.map { #""max_tool_calls":\#($0),"# } ?? ""
    return #"{"model":"\#(slug)","input":"latest Swift","stream":\#(streaming),"#
        + maximum
        + #""tools":["#
        + #"{"type":"web_search"},{"type":"function","name":"weather","parameters":{"type":"object"}}]}"#
}
