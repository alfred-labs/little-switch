import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses web search streaming projection")
struct OpenAIResponsesWebSearchStreamingTests {
    @Test("Streaming emits native lifecycles and one terminal response")
    func streamingProjection() throws {
        let fixture = try streamingFixture(text: "Swift is current.")
        let body = try OpenAIResponsesWebSearch.streamingResponse(
            prepared: fixture.prepared,
            traces: [fixture.trace],
            finalTurn: fixture.finalTurn,
            usage: ResponsesUsage(inputTokens: 20, outputTokens: 9)
        )
        let events = try ResponsesStreamingTestSupport.events(body)
        let names = events.map(\.name)

        #expect(Array(names.prefix(2)) == ["response.created", "response.in_progress"])
        let searchStart = try #require(names.firstIndex(of: "response.web_search_call.in_progress"))
        #expect(
            Array(names[(searchStart - 1)...(searchStart + 3)])
                == [
                    "response.output_item.added",
                    "response.web_search_call.in_progress",
                    "response.web_search_call.searching",
                    "response.web_search_call.completed",
                    "response.output_item.done",
                ]
        )
        let searchAdded = try #require(events[searchStart - 1].payload["item"] as? [String: Any])
        #expect(
            NSDictionary(dictionary: searchAdded).isEqual(to: [
                "id": "ws_search",
                "type": "web_search_call",
                "status": "in_progress",
            ])
        )
        let searchDone = try #require(events[searchStart + 3].payload["item"] as? [String: Any])
        #expect(
            NSDictionary(dictionary: searchDone).isEqual(to: [
                "id": "ws_search",
                "type": "web_search_call",
                "status": "completed",
                "action": ["type": "search", "query": "Swift 6.3"],
            ])
        )
        #expect(names.contains("response.reasoning_summary_text.delta"))
        #expect(names.contains("response.reasoning_summary_text.done"))
        #expect(names.contains("response.function_call_arguments.delta"))
        #expect(names.contains("response.function_call_arguments.done"))
        #expect(names.contains("response.content_part.added"))
        #expect(names.contains("response.output_text.delta"))
        #expect(names.contains("response.output_text.done"))
        #expect(names.filter { $0 == "response.completed" }.count == 1)
        #expect(events.compactMap(\.sequenceNumber) == Array(events.indices))
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(!stream.contains(#""name":"web_search""#))
        #expect(!stream.contains("provider-secret"))

        for eventName in ["response.created", "response.in_progress"] {
            let response = try #require(
                events.first { $0.name == eventName }?.payload["response"] as? [String: Any]
            )
            #expect(response["metadata"] as? [String: String] == ["owner": "client"])
            #expect(response["parallel_tool_calls"] as? Bool == true)
            #expect(response["provider_secret"] == nil)
        }
        let messageAddedEvent = events.first {
            $0.name == "response.output_item.added"
                && ($0.payload["item"] as? [String: Any])?["id"] as? String == "msg_final"
        }
        let messageAdded = try #require(
            messageAddedEvent?.payload["item"] as? [String: Any]
        )
        #expect(messageAdded["provider_secret"] == nil)
        let contentAdded = try #require(
            events.first { $0.name == "response.content_part.added" }?
                .payload["part"] as? [String: Any]
        )
        #expect(Set(contentAdded.keys) == ["type", "text", "annotations", "logprobs"])
        let contentDone = try #require(
            events.first { $0.name == "response.content_part.done" }?
                .payload["part"] as? [String: Any]
        )
        #expect(Set(contentDone.keys) == ["type", "text", "annotations", "logprobs"])
        let messageDoneEvent = events.first {
            $0.name == "response.output_item.done"
                && ($0.payload["item"] as? [String: Any])?["id"] as? String == "msg_final"
        }
        let messageDone = try #require(
            messageDoneEvent?.payload["item"] as? [String: Any]
        )
        #expect(messageDone["provider_secret"] == nil)

        let completedEvent = try #require(events.last)
        #expect(completedEvent.name == "response.completed")
        let completed = try #require(completedEvent.payload["response"] as? [String: Any])
        #expect(completed["metadata"] as? [String: String] == ["owner": "client"])
        #expect(completed["parallel_tool_calls"] as? Bool == true)
        #expect(completed["provider_secret"] == nil)
        let expectedData = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: fixture.prepared,
            traces: [fixture.trace],
            finalTurn: fixture.finalTurn,
            usage: ResponsesUsage(inputTokens: 20, outputTokens: 9)
        )
        let expected = try #require(
            JSONSerialization.jsonObject(with: expectedData) as? [String: Any]
        )
        #expect(NSDictionary(dictionary: completed).isEqual(to: expected))
    }

    @Test("Empty output text completes without a synthetic delta")
    func emptyText() throws {
        let fixture = try streamingFixture(text: "")
        let events = try ResponsesStreamingTestSupport.events(
            OpenAIResponsesWebSearch.streamingResponse(
                prepared: fixture.prepared,
                traces: [fixture.trace],
                finalTurn: fixture.finalTurn,
                usage: ResponsesUsage(inputTokens: 2, outputTokens: 1)
            )
        )
        let messageEvents = events.filter { event in
            event.payload["item_id"] as? String == "msg_final"
        }
        #expect(!messageEvents.contains { $0.name == "response.output_text.delta" })
        #expect(messageEvents.contains { $0.name == "response.output_text.done" })
        #expect(messageEvents.contains { $0.name == "response.content_part.done" })
    }

    @Test(
        "Streaming encoder derives its terminal event from response status",
        arguments: [
            ("completed", "response.completed"),
            ("incomplete", "response.incomplete"),
        ]
    )
    func terminalStatus(status: String, expectedEvent: String) throws {
        let response = terminalResponseFixture(status: status)
        let events = try ResponsesStreamingTestSupport.events(
            OpenAIResponsesStreaming.encode(completed: response)
        )
        let terminal = try #require(events.last)

        #expect(terminal.name == expectedEvent)
        #expect(terminal.payload["type"] as? String == expectedEvent)
        let terminalResponse = try #require(terminal.payload["response"] as? [String: Any])
        #expect(NSDictionary(dictionary: terminalResponse).isEqual(to: response))
        let terminalNames = events.map(\.name).filter {
            ["response.completed", "response.incomplete", "response.failed"].contains($0)
        }
        #expect(terminalNames == [expectedEvent])
        if status == "incomplete" {
            #expect(!events.map(\.name).contains("response.completed"))
        }
    }

    @Test("Failed fallback emits only a sanitized native error lifecycle")
    func safeFailedFallback() throws {
        var response = terminalResponseFixture(status: "failed")
        response["error"] = [
            "code": "provider_secret_code",
            "message": "secret upstream response body",
        ]

        let body = try OpenAIResponsesStreaming.encode(completed: response)
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(
            events.map(\.name)
                == [
                    "response.created",
                    "response.in_progress",
                    "error",
                    "response.failed",
                ]
        )
        try #require(events.count == 4)
        #expect(events.compactMap(\.sequenceNumber) == Array(events.indices))

        let created = try #require(events[0].payload["response"] as? [String: Any])
        #expect(created["status"] as? String == "in_progress")
        #expect(created["error"] is NSNull)

        let error = events[2].payload
        #expect(
            Set(error.keys)
                == ["type", "sequence_number", "code", "message", "param"]
        )
        #expect(error["code"] as? String == "server_error")
        #expect(error["message"] as? String == "Internal server error")
        #expect(error["param"] is NSNull)

        let failed = try #require(events[3].payload["response"] as? [String: Any])
        #expect(failed["status"] as? String == "failed")
        #expect(
            failed["error"] as? [String: String]
                == [
                    "code": "server_error",
                    "message": "Internal server error",
                ]
        )
        let stream = try #require(String(data: body, encoding: .utf8))
        #expect(!stream.contains("secret"))
        #expect(!stream.contains("provider_secret_code"))
    }

    @Test("Streaming encoder rejects unknown or missing terminal status")
    func invalidTerminalStatus() {
        for response in [
            terminalResponseFixture(status: nil),
            terminalResponseFixture(status: "cancelled"),
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesStreaming.encode(completed: response)
            }
        }
    }

    @Test("Streaming encoder rejects function calls without a non-empty name")
    func invalidFunctionName() {
        let namelessCall: [String: Any] = [
            "id": "fc_test",
            "type": "function_call",
            "status": "completed",
            "arguments": "{}",
        ]
        var emptyNameCall = namelessCall
        emptyNameCall["name"] = ""

        for item in [namelessCall, emptyNameCall] {
            var response = terminalResponseFixture(status: "completed")
            response["output"] = [item]
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesStreaming.encode(completed: response)
            }
        }
    }

    @Test("Streaming encoder rejects a completed response without output")
    func missingOutput() {
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesStreaming.encode(completed: ["status": "completed"])
        }
    }
}

private struct StreamingFixture {
    let prepared: PreparedResponsesWebSearchRequest
    let trace: ResponsesWebSearchTrace
    let finalTurn: ResponsesModelTurn
}

private func terminalResponseFixture(status: String?) -> [String: Any] {
    var response: [String: Any] = [
        "id": "resp_terminal",
        "object": "response",
        "created_at": 40,
        "completed_at": 45,
        "output": [],
        "incomplete_details": ["reason": "max_output_tokens"],
        "usage": ["input_tokens": 1, "output_tokens": 2, "total_tokens": 3],
    ]
    if let status {
        response["status"] = status
    }
    return response
}

// The poisoned fixture keeps all buffered item families in one ordered response.
// swiftlint:disable:next function_body_length
private func streamingFixture(text: String) throws -> StreamingFixture {
    let request = try JSONSerialization.data(
        withJSONObject: [
            "model": "little-switch-slug",
            "input": "latest Swift",
            "stream": true,
            "metadata": ["owner": "client"],
            "parallel_tool_calls": true,
            "tools": [
                ["type": "web_search"],
                ["type": "function", "name": "weather", "parameters": ["type": "object"]],
            ],
        ]
    )
    let candidate = try OpenAIResponsesWebSearch.prepare(
        body: request,
        targetModel: "glm-5.3",
        configuration: .firecrawlCloud
    )
    let prepared = try #require(candidate)
    let searchTurn = try streamingTurn(
        id: "resp_search",
        output: [
            [
                "id": "rs_search",
                "type": "reasoning",
                "summary": [
                    [
                        "type": "summary_text",
                        "text": "Need current info",
                        "provider_secret": "provider-secret-summary-part",
                    ]
                ],
                "provider_secret": "provider-secret-reasoning-item",
            ],
            [
                "id": "fc_search",
                "type": "function_call",
                "status": "completed",
                "name": "web_search",
                "call_id": "call_search",
                "arguments": #"{"query":"Swift 6.3"}"#,
            ],
            [
                "id": "fc_weather",
                "type": "function_call",
                "status": "completed",
                "name": "weather",
                "call_id": "call_weather",
                "arguments": #"{"city":"Paris"}"#,
                "provider_secret": "provider-secret-function-item",
            ],
        ]
    )
    let finalTurn = try streamingTurn(
        id: "resp_final",
        output: [
            [
                "id": "msg_final",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "phase": "final_answer",
                "content": [
                    [
                        "type": "output_text",
                        "text": text,
                        "annotations": [
                            [
                                "type": "url_citation",
                                "start_index": 0,
                                "end_index": 5,
                                "title": "Swift",
                                "url": "https://swift.org/",
                                "provider_secret": "provider-secret-annotation",
                            ]
                        ],
                        "logprobs": [
                            [
                                "token": "Swift",
                                "logprob": -0.1,
                                "bytes": [83],
                                "provider_secret": "provider-secret-logprob",
                            ]
                        ],
                        "provider_secret": "provider-secret-content-part",
                    ]
                ],
                "provider_secret": "provider-secret-message-item",
            ]
        ]
    )
    return StreamingFixture(
        prepared: prepared,
        trace: ResponsesWebSearchTrace(
            id: "ws_search",
            callID: "call_search",
            query: "Swift 6.3",
            outputJSON: searchTurn.outputJSON
        ),
        finalTurn: finalTurn
    )
}

private func streamingTurn(
    id: String,
    output: [[String: Any]]
) throws -> ResponsesModelTurn {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "id": id,
            "object": "response",
            "created_at": 40,
            "completed_at": 45,
            "status": "completed",
            "model": "glm-5.3",
            "output": output,
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
            "metadata": [
                "owner": "provider",
                "provider_secret": "provider-secret-root-metadata",
            ],
            "parallel_tool_calls": false,
            "provider_secret": "provider-secret-root",
        ],
        options: [.sortedKeys]
    )
    return try OpenAIResponsesWebSearch.parseModelTurn(body)
}

enum ResponsesStreamingTestSupport {
    struct Event {
        let name: String
        let payload: [String: Any]

        var sequenceNumber: Int? {
            payload["sequence_number"] as? Int
        }
    }

    static func events(_ data: Data) throws -> [Event] {
        let stream = try #require(String(data: data, encoding: .utf8))
        return
            try stream
            .components(separatedBy: "\n\n")
            .filter { !$0.isEmpty }
            .map { block in
                let lines = block.components(separatedBy: "\n")
                guard lines.count == 2,
                    lines[0].hasPrefix("event: "),
                    lines[1].hasPrefix("data: "),
                    let payload = try JSONSerialization.jsonObject(
                        with: Data(lines[1].dropFirst(6).utf8)
                    ) as? [String: Any]
                else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                return Event(
                    name: String(lines[0].dropFirst(7)),
                    payload: payload
                )
            }
    }
}
