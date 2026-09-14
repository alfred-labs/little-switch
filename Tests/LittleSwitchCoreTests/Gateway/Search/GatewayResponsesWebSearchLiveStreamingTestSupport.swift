import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

func liveResponsesSearchContext(
    fixture: GatewayFixture,
    native: Bool = false,
    maxToolCalls: Int? = nil
) throws -> GatewayResponsesWebSearchContext {
    let mapping = try #require(
        fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
    )
    let originalTarget = try #require(
        fixture.snapshot.resolveCodex(model: CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers))
    )
    let provider: Provider
    if native {
        provider = Provider(
            id: originalTarget.provider.id,
            name: "Native Responses",
            baseURL: "https://responses.example/api",
            authMode: originalTarget.provider.authMode,
            models: originalTarget.provider.models
        )
    } else {
        provider = originalTarget.provider
    }
    let target = CodexModelTarget(provider: provider, model: originalTarget.model)
    let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
    let body = try liveResponsesSearchRequest(
        slug: slug,
        maxToolCalls: maxToolCalls
    )
    let prepared = try #require(
        try OpenAIResponsesWebSearch.prepare(
            body: body,
            targetModel: target.model.id,
            configuration: fixture.snapshot.webSearch
        )
    )
    return GatewayResponsesWebSearchContext(
        prepared: prepared,
        configuration: fixture.snapshot.webSearch,
        target: target,
        providerCredential: "selected-secret",
        searchCredential: "firecrawl-secret",
        incomingHeaders: [:],
        eventID: UUID(),
        needsChatCompletionsAdapter: !native
    )
}

func liveResponsesSearchRequest(
    slug: String,
    maxToolCalls: Int? = nil
) throws -> Data {
    var request: [String: Any] = [
        "model": slug,
        "input": "latest Swift",
        "stream": true,
        "tools": [
            [
                "type": "web_search",
                "external_web_access": true,
                "filters": ["allowed_domains": ["swift.org"]],
                "user_location": [
                    "type": "approximate",
                    "city": "Paris",
                    "region": "Ile-de-France",
                    "country": "FR",
                    "timezone": "Europe/Paris",
                ],
                "search_context_size": "high",
                "search_content_types": ["text"],
            ],
            [
                "type": "function",
                "name": "weather",
                "parameters": ["type": "object"],
            ],
        ],
    ]
    if let maxToolCalls {
        request["max_tool_calls"] = maxToolCalls
    }
    return try JSONSerialization.data(
        withJSONObject: request,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

func nativeFailedJSON(code: String) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "id": "resp_native_failed",
            "object": "response",
            "created_at": 95,
            "status": "failed",
            "error": [
                "code": code,
                "message": "provider-secret-message",
            ],
            "usage": NSNull(),
        ],
        options: [.sortedKeys]
    )
    return try #require(String(data: data, encoding: .utf8))
}

func liveNativeSearchFrames(
    responseID: String = "resp_native_search",
    query: String = "latest Swift"
) throws -> [ServerSentEventFrame] {
    let call = functionCallItem(
        id: "fc_private_search",
        callID: "call_private_search",
        name: "web_search",
        arguments: #"{"query":"\#(query)"}"#,
        status: "completed"
    )
    let started = functionCallItem(
        id: "fc_private_search",
        callID: "call_private_search",
        name: "web_search",
        arguments: "",
        status: "in_progress"
    )
    return try [
        createdFrame(id: responseID, createdAt: 100),
        responsesFrame(
            "response.output_item.added",
            ["output_index": 7, "item": started]
        ),
        responsesFrame(
            "response.function_call_arguments.delta",
            [
                "output_index": 7,
                "item_id": "fc_private_search",
                "delta": #"{"query":"latest "#,
            ]
        ),
        responsesFrame(
            "response.function_call_arguments.delta",
            [
                "output_index": 7,
                "item_id": "fc_private_search",
                "delta": #"Swift"}"#,
            ]
        ),
        responsesFrame(
            "response.function_call_arguments.done",
            [
                "output_index": 7,
                "item_id": "fc_private_search",
                "name": "web_search",
                "arguments": #"{"query":"\#(query)"}"#,
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 7, "item": call]
        ),
        responsesFrame(
            "response.completed",
            [
                "response": responseObject(
                    id: responseID,
                    createdAt: 100,
                    status: "completed",
                    output: [call],
                    usage: ResponsesUsage(inputTokens: 3, outputTokens: 2)
                )
            ]
        ),
    ]
}

func liveNativeFinalChunks() throws -> [Data] {
    let started: [String: Any] = [
        "id": "msg_native_final",
        "type": "message",
        "status": "in_progress",
        "role": "assistant",
        "content": [],
    ]
    let done: [String: Any] = [
        "id": "msg_native_final",
        "type": "message",
        "status": "completed",
        "role": "assistant",
        "content": [outputTextPart("FIRST SECOND")],
    ]
    let early = try responsesGatewaySSE([
        createdFrame(id: "resp_native_final", createdAt: 101),
        responsesFrame(
            "response.output_item.added",
            ["output_index": 4, "item": started]
        ),
        responsesFrame(
            "response.content_part.added",
            [
                "output_index": 4,
                "content_index": 9,
                "item_id": "msg_native_final",
                "part": outputTextPart(""),
            ]
        ),
        responsesFrame(
            "response.output_text.delta",
            [
                "output_index": 4,
                "content_index": 9,
                "item_id": "msg_native_final",
                "delta": "FIRST",
                "logprobs": [],
            ]
        ),
    ])
    let tail = try responsesGatewaySSE([
        responsesFrame(
            "response.output_text.delta",
            [
                "output_index": 4,
                "content_index": 9,
                "item_id": "msg_native_final",
                "delta": " SECOND",
                "logprobs": [],
            ]
        ),
        responsesFrame(
            "response.output_text.done",
            [
                "output_index": 4,
                "content_index": 9,
                "item_id": "msg_native_final",
                "text": "FIRST SECOND",
                "logprobs": [],
            ]
        ),
        responsesFrame(
            "response.content_part.done",
            [
                "output_index": 4,
                "content_index": 9,
                "item_id": "msg_native_final",
                "part": outputTextPart("FIRST SECOND"),
            ]
        ),
        responsesFrame(
            "response.output_item.done",
            ["output_index": 4, "item": done]
        ),
        responsesFrame(
            "response.completed",
            [
                "response": responseObject(
                    id: "resp_native_final",
                    createdAt: 101,
                    status: "completed",
                    output: [done],
                    usage: ResponsesUsage(inputTokens: 5, outputTokens: 4)
                )
            ]
        ),
    ])
    return [early, tail]
}

func liveZAIPrivateSearchChunks() throws -> [Data] {
    let chunks: [[String: Any]] = [
        liveZAIChunk(choices: [
            liveZAIChoice(delta: [
                "role": "assistant",
                "tool_calls": [
                    liveZAIToolDelta(
                        id: "call_private_search",
                        name: "web_search",
                        arguments: #"{"query":"latest "#
                    )
                ],
            ])
        ]),
        liveZAIChunk(choices: [
            liveZAIChoice(delta: [
                "tool_calls": [liveZAIToolDelta(arguments: #"Swift"}"#)]
            ])
        ]),
        liveZAIChunk(choices: [
            liveZAIChoice(delta: [:], finishReason: "tool_calls")
        ]),
        liveZAIChunk(
            choices: [],
            usage: [
                "prompt_tokens": 3,
                "completion_tokens": 2,
                "total_tokens": 5,
            ]
        ),
    ]
    return [try liveZAISSE(chunks) + Data("data: [DONE]\n\n".utf8)]
}

func liveZAIFinalChunks() throws -> [Data] {
    let chunks: [[String: Any]] = [
        liveZAIChunk(
            choices: [
                liveZAIChoice(delta: ["role": "assistant", "content": "FIRST"])
            ], id: "chatcmpl_final"),
        liveZAIChunk(
            choices: [
                liveZAIChoice(delta: ["content": " SECOND"])
            ], id: "chatcmpl_final"),
        liveZAIChunk(
            choices: [
                liveZAIChoice(delta: [:], finishReason: "stop")
            ], id: "chatcmpl_final"),
        liveZAIChunk(
            choices: [],
            usage: [
                "prompt_tokens": 5,
                "completion_tokens": 4,
                "total_tokens": 9,
            ],
            id: "chatcmpl_final"
        ),
    ]
    return [try liveZAISSE(chunks) + Data("data: [DONE]\n\n".utf8)]
}

func responsesGatewaySSE(_ frames: [ServerSentEventFrame]) throws -> Data {
    var body = Data()
    for frame in frames {
        let event = try #require(frame.event)
        body.append(Data("event: \(event)\ndata: ".utf8))
        body.append(frame.data)
        body.append(Data("\n\n".utf8))
    }
    return body
}

func assertNativeResponsesSearchContract(
    events: [ResponsesStreamingTestSupport.Event],
    requests: [RecordedGatewayRequest]
) throws {
    #expect(events.map(\.sequenceNumber) == Array(0..<events.count).map(Optional.some))
    #expect(events.first?.name == "response.created")
    #expect(events.last?.name == "response.completed")
    #expect(events.filter { $0.name == "response.created" }.count == 1)
    #expect(events.filter { $0.name == "response.completed" }.count == 1)
    #expect(!events.contains { $0.name == "response.failed" })

    let searchAdded = try #require(
        events.first { $0.name == "response.output_item.added" }
    )
    let addedItem = try #require(searchAdded.payload["item"] as? [String: Any])
    #expect(addedItem["type"] as? String == "web_search_call")
    #expect(addedItem["status"] as? String == "in_progress")
    #expect(addedItem["action"] == nil)
    let searchID = try #require(addedItem["id"] as? String)

    let searchDone = try #require(
        events.first { event in
            guard event.name == "response.output_item.done",
                let item = event.payload["item"] as? [String: Any]
            else {
                return false
            }
            return item["type"] as? String == "web_search_call"
        }
    )
    let doneItem = try #require(searchDone.payload["item"] as? [String: Any])
    #expect(doneItem["id"] as? String == searchID)
    try assertGatewayResponsesSearchItem(
        doneItem,
        query: "latest Swift",
        sources: ["https://swift.org/"]
    )
    #expect(searchAdded.payload["output_index"] as? Int == 0)
    #expect(searchDone.payload["output_index"] as? Int == 0)

    let terminal = try #require(events.last?.payload["response"] as? [String: Any])
    let created = try #require(events.first?.payload["response"] as? [String: Any])
    #expect(terminal["id"] as? String == created["id"] as? String)
    let output = try #require(terminal["output"] as? [[String: Any]])
    #expect(output.compactMap { $0["type"] as? String } == ["web_search_call", "message"])
    #expect(NSDictionary(dictionary: try #require(output.first)).isEqual(to: doneItem))
    #expect(output.allSatisfy { $0["name"] as? String != "web_search" })
    #expect(terminal["tools"] is [[String: Any]])

    try #require(requests.count == 3)
    #expect(
        requests.map(\.url) == [
            "https://responses.example/api/v1/responses",
            "https://api.firecrawl.dev/v2/search",
            "https://responses.example/api/v1/responses",
        ]
    )
    let firecrawl = try responsesGatewayObject(requests[1].body)
    #expect(firecrawl["includeDomains"] as? [String] == ["swift.org"])
    #expect(firecrawl["location"] as? String == "Paris, Ile-de-France")
    #expect(firecrawl["country"] as? String == "FR")
    #expect(try responsesGatewayObject(requests[2].body)["stream"] as? Bool == true)
}

func liveResponsesStreamingResponse<S: AsyncSequence & Sendable>(
    _ sequence: S
) -> HTTPClientResponse where S.Element == ByteBuffer {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": "text/event-stream"],
        body: .stream(sequence)
    )
}

private func liveZAIChunk(
    choices: [[String: Any]],
    usage: [String: Any]? = nil,
    id: String = "chatcmpl_search"
) -> [String: Any] {
    var object: [String: Any] = [
        "id": id,
        "object": "chat.completion.chunk",
        "created": 200,
        "model": "glm-5.2",
        "choices": choices,
    ]
    if let usage {
        object["usage"] = usage
    }
    return object
}

private func liveZAIChoice(
    delta: [String: Any],
    finishReason: String? = nil
) -> [String: Any] {
    [
        "index": 0,
        "delta": delta,
        "finish_reason": finishReason ?? NSNull(),
    ]
}

private func liveZAIToolDelta(
    id: String? = nil,
    name: String? = nil,
    arguments: String
) -> [String: Any] {
    var call: [String: Any] = ["index": 0]
    if let id {
        call["id"] = id
        call["type"] = "function"
    }
    var function: [String: Any] = ["arguments": arguments]
    if let name {
        function["name"] = name
    }
    call["function"] = function
    return call
}

private func liveZAISSE(_ chunks: [[String: Any]]) throws -> Data {
    var body = Data()
    for chunk in chunks {
        body.append(Data("data: ".utf8))
        body.append(
            try JSONSerialization.data(
                withJSONObject: chunk,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        )
        body.append(Data("\n\n".utf8))
    }
    return body
}
