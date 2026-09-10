import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses Chat Completions adapter")
struct OpenAIResponsesChatCompletionsTests {
    @Test("Responses text, function history, and tools become a buffered Chat request")
    func preparesChatRequest() throws {
        let body = Data(
            #"""
            {
              "model":"little-switch-route",
              "instructions":"Follow the project rules.",
              "input":[
                {"type":"message","role":"developer","content":[{"type":"input_text","text":"Be concise."}]},
                {"type":"message","role":"user","content":[{"type":"input_text","text":"Inspect it."}]},
                {"type":"function_call","call_id":"call_1","name":"read_file","arguments":"{\"path\":\"README.md\"}"},
                {"type":"function_call_output","call_id":"call_1","output":"Done"}
              ],
              "tools":[
                {"type":"function","name":"read_file","description":"Read a file.","parameters":{"type":"object"}},
                {"type":"namespace","name":"apps","description":"Connected apps.","tools":[]}
              ],
              "tool_choice":"auto",
              "parallel_tool_calls":true,
              "max_output_tokens":512,
              "temperature":0.25,
              "top_p":0.9,
              "stream":true
            }
            """#.utf8
        )

        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: "glm-5.3-flash"
        )
        let request = try object(prepared.upstreamBody)

        #expect(prepared.originalModel == "little-switch-route")
        #expect(prepared.streaming)
        #expect(request["model"] as? String == "glm-5.3-flash")
        #expect(request["stream"] as? Bool == false)
        #expect(request["tool_stream"] == nil)
        #expect(request["parallel_tool_calls"] as? Bool == true)
        #expect(request["max_tokens"] as? Int == 512)
        #expect(request["temperature"] as? Double == 0.25)
        #expect(request["top_p"] as? Double == 0.9)

        let messages = try #require(request["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["system", "system", "user", "assistant", "tool"])
        #expect(messages[0]["content"] as? String == "Follow the project rules.")
        #expect(messages[1]["content"] as? String == "Be concise.")
        #expect(messages[2]["content"] as? String == "Inspect it.")
        let historyCalls = try #require(messages[3]["tool_calls"] as? [[String: Any]])
        #expect(historyCalls[0]["id"] as? String == "call_1")
        #expect((historyCalls[0]["function"] as? [String: Any])?["name"] as? String == "read_file")
        #expect(messages[4]["tool_call_id"] as? String == "call_1")
        #expect(messages[4]["content"] as? String == "Done")

        let tools = try #require(request["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        #expect((tools[0]["function"] as? [String: Any])?["name"] as? String == "read_file")
    }

    @Test("A Chat text response becomes a completed Responses JSON object")
    func projectsTextResponse() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"little-switch-route","input":"Hello","stream":false,"store":false}"#.utf8
            ),
            targetModel: "glm-5.3-flash"
        )
        let body = try OpenAIResponsesChatCompletions.project(
            responseBody: Data(
                #"""
                {
                  "id":"chatcmpl_1",
                  "object":"chat.completion",
                  "created":42,
                  "model":"glm-5.3-flash",
                  "choices":[
                    {"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"OK"}}
                  ],
                  "usage":{"prompt_tokens":7,"completion_tokens":2,"total_tokens":9}
                }
                """#.utf8
            ),
            prepared: prepared
        )
        let response = try object(body)

        #expect(response["id"] as? String == "resp_chatcmpl_1")
        #expect(response["object"] as? String == "response")
        #expect(response["status"] as? String == "completed")
        #expect(response["model"] as? String == "little-switch-route")
        #expect(response["store"] as? Bool == false)
        let output = try #require(response["output"] as? [[String: Any]])
        #expect(output.count == 1)
        #expect(output[0]["type"] as? String == "message")
        let content = try #require(output[0]["content"] as? [[String: Any]])
        #expect(content[0]["type"] as? String == "output_text")
        #expect(content[0]["text"] as? String == "OK")
        let usage = try #require(response["usage"] as? [String: Any])
        #expect(usage["input_tokens"] as? Int == 7)
        #expect(usage["output_tokens"] as? Int == 2)
        #expect(usage["total_tokens"] as? Int == 9)
    }

    @Test("A Chat tool call becomes a Responses SSE function call")
    func projectsToolCallStream() throws {
        let functionID = "fc_resp_chatcmpl_tools_0"
        let functionIndex = 0
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"little-switch-route","input":"Inspect","stream":true,"parallel_tool_calls":true}"#.utf8
            ),
            targetModel: "glm-5.3-flash"
        )
        let body = try OpenAIResponsesChatCompletions.project(
            responseBody: Data(
                #"""
                {
                  "id":"chatcmpl_tools",
                  "created":50,
                  "choices":[
                    {
                      "finish_reason":"tool_calls",
                      "message":{
                        "role":"assistant",
                        "content":null,
                        "tool_calls":[
                          {
                            "id":"call_read",
                            "type":"function",
                            "function":{"name":"read_file","arguments":"{\"path\":\"README.md\"}"}
                          }
                        ]
                      }
                    }
                  ]
                }
                """#.utf8
            ),
            prepared: prepared
        )
        let events = try ResponsesStreamingTestSupport.events(body)
        let stream = try #require(String(data: body, encoding: .utf8))

        #expect(stream.contains("event: response.created\n"))
        #expect(stream.contains("event: response.function_call_arguments.delta\n"))
        #expect(stream.contains(#""call_id":"call_read""#))
        #expect(stream.contains("event: response.completed\n"))

        let deltaEvent = try #require(
            events.first { $0.name == "response.function_call_arguments.delta" }
        )
        var deltaPayload = deltaEvent.payload
        deltaPayload.removeValue(forKey: "type")
        deltaPayload.removeValue(forKey: "sequence_number")
        #expect(
            NSDictionary(dictionary: deltaPayload).isEqual(to: [
                "item_id": functionID,
                "output_index": functionIndex,
                "delta": #"{"path":"README.md"}"#,
            ])
        )

        let doneEvent = try #require(
            events.first { $0.name == "response.function_call_arguments.done" }
        )
        var donePayload = doneEvent.payload
        donePayload.removeValue(forKey: "type")
        donePayload.removeValue(forKey: "sequence_number")
        #expect(
            NSDictionary(dictionary: donePayload).isEqual(to: [
                "item_id": functionID,
                "output_index": functionIndex,
                "name": "read_file",
                "arguments": #"{"path":"README.md"}"#,
            ])
        )
    }

    @Test("Filtered hosted tools cannot leave a required Chat tool choice")
    func dropsImpossibleToolChoice() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(
                #"{"model":"slug","input":"latest","tools":[{"type":"web_search"}],"tool_choice":"required"}"#
                    .utf8
            ),
            targetModel: "glm"
        )
        let request = try object(prepared.upstreamBody)
        #expect(request["tools"] == nil)
        #expect(request["tool_choice"] == nil)
    }

    @Test("Malformed adapter input and output are rejected")
    func rejectsMalformedBodies() throws {
        let invalidRequests = [
            #"{"model":"","input":"Hello"}"#,
            #"{"model":"route","input":1}"#,
            #"{"model":"route","input":[{"type":"reasoning"}]}"#,
            #"{"model":"route","input":[{"type":"unknown"}]}"#,
            #"{"model":"route","input":[{"type":"function_call","call_id":"call","name":"read"}]}"#,
            #"{"model":"route","input":[{"type":"function_call_output","call_id":"call"}]}"#,
            #"{"model":"route","input":[{"type":"message","content":"hello"}]}"#,
            #"{"model":"route","input":[{"type":"message","role":"tool","content":"hello"}]}"#,
            #"{"model":"route","input":[{"type":"message","role":"user","content":1}]}"#,
            #"{"model":"route","input":[{"type":"message","role":"user","content":[{"type":"image"}]}]}"#,
            #"{"model":"route","input":[{"type":"message","role":"user","content":[{"type":"input_text"}]}]}"#,
        ]
        for request in invalidRequests {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try OpenAIResponsesChatCompletions.prepare(
                    body: Data(request.utf8),
                    targetModel: "glm-5.3-flash"
                )
            }
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try OpenAIResponsesChatCompletions.prepare(
                body: Data(#"{"model":"route","input":"Hello"}"#.utf8),
                targetModel: ""
            )
        }
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(#"{"model":"route","input":"Hello"}"#.utf8),
            targetModel: "glm-5.3-flash"
        )
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try OpenAIResponsesChatCompletions.project(
                responseBody: Data("{}".utf8),
                prepared: prepared
            )
        }
        for response in [
            #"{"choices":[{"message":{"role":"assistant","content":1}}]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{}]}}]}"#,
        ] {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try OpenAIResponsesChatCompletions.project(
                    responseBody: Data(response.utf8),
                    prepared: prepared
                )
            }
        }
    }

    @Test("Adapter covers optional history, choice, incomplete, and empty response shapes")
    func optionalShapes() throws {
        let requestBody =
            #"""
            {
              "model": "route",
              "input": [
                {"type": "reasoning"},
                {"type": "message", "role": "assistant", "content": "Prior"},
                {
                  "type": "function_call_output",
                  "call_id": "call",
                  "output": {"ok": true}
                },
                {
                  "type": "message",
                  "role": "user",
                  "content": [{"type": "output_text", "text": "Continue"}]
                }
              ],
              "tools": [
                {"type": "function", "name": "read", "parameters": {"type": "object"}}
              ],
              "tool_choice": {"type": "function", "name": "read"}
            }
            """#
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: Data(requestBody.utf8),
            targetModel: "glm-5.3-flash"
        )
        let request = try object(prepared.upstreamBody)
        let messages = try #require(request["messages"] as? [[String: Any]])
        #expect(messages[0]["content"] as? String == "Prior")
        #expect(messages[1]["content"] as? String == #"{"ok":true}"#)
        #expect(messages[2]["content"] as? String == "Continue")
        #expect(
            ((request["tool_choice"] as? [String: Any])?["function"] as? [String: Any])?["name"]
                as? String == "read"
        )

        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: Data(
                #"{"id":"resp_existing","choices":[{"finish_reason":"length","message":{"role":"assistant","content":null}}],"usage":{"prompt_tokens":2,"completion_tokens":3}}"#
                    .utf8
            ),
            prepared: prepared
        )
        let response = try object(projected)
        #expect(response["id"] as? String == "resp_existing")
        #expect(response["status"] as? String == "incomplete")
        #expect((response["incomplete_details"] as? [String: Any])?["reason"] as? String == "max_output_tokens")
        let output = try #require(response["output"] as? [[String: Any]])
        let content = try #require(output[0]["content"] as? [[String: Any]])
        #expect((content[0]["text"] as? String)?.isEmpty == true)
        #expect((response["usage"] as? [String: Any])?["total_tokens"] as? Int == 5)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
