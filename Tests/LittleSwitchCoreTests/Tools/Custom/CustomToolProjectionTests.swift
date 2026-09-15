import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

extension JSONValue {
    fileprivate subscript(key: String) -> JSONValue? { object?[key] }
    fileprivate subscript(index: Int) -> JSONValue? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

@Suite("Conditional custom tool projection")
struct CustomToolProjectionTests {
    @Test("Native support preserves every original request and response byte")
    func nativeIdentity() throws {
        let request = Data(#"{ "model":"m", "tools":[{"type":"custom","name":"exec"}], "input":"go" }"#.utf8)
        let response = Data(#"{ "output":[{"type":"custom_tool_call","name":"exec","input":"  x\r\n"}] }"#.utf8)
        let projection = try CustomToolProjection.prepare(body: request, wire: .responses, adapt: false)
        #expect(projection.upstreamBody == request)
        #expect(projection.originalBody == request)
        #expect(try projection.restoreBuffered(response) == response)
    }

    @Test("Responses custom input and forced selection use the same function envelope")
    func responsesRoundTrip() throws {
        let body = Data(
            #"""
            {
              "model": "m",
              "tools": [
                {
                  "type": "function",
                  "name": "exec_command",
                  "parameters": {}
                },
                {
                  "type": "custom",
                  "name": "exec",
                  "description": "Run JS",
                  "format": {
                    "type": "text"
                  }
                }
              ],
              "tool_choice": {
                "type": "custom",
                "name": "exec"
              },
              "input": [
                {
                  "type": "custom_tool_call",
                  "call_id": "old",
                  "name": "exec",
                  "input": "  text(\"é\");\r\n"
                },
                {
                  "type": "custom_tool_call_output",
                  "call_id": "old",
                  "output": "ok"
                }
              ]
            }
            """#.utf8)
        let projection = try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true)
        let wire = try JSONValue.parse(projection.upstreamBody)
        #expect(wire["tools"]?[0]?["name"] == .string("exec_command"))
        #expect(wire["tools"]?[1]?["type"] == .string("function"))
        #expect(wire["tools"]?[1]?["parameters"]?["required"] == .array([.string("input")]))
        #expect(wire["tool_choice"] == .object(["type": .string("function"), "name": .string("exec")]))
        #expect(wire["input"]?[0]?["type"] == .string("function_call"))
        #expect(wire["input"]?[1]?["type"] == .string("function_call_output"))
        let response = Data(
            #"""
            {
              "output": [
                {
                  "id": "fc1",
                  "type": "function_call",
                  "call_id": "new",
                  "name": "exec",
                  "arguments": "{\"input\":\"  text(\\\"é\\\");\\r\\n\"}",
                  "status": "completed"
                }
              ],
              "usage": {
                "output_tokens": 3
              }
            }
            """#.utf8)
        let restored = try JSONValue.parse(projection.restoreBuffered(response))
        let expected = try JSONValue.parse(
            Data(
                #"{"output":[{"id":"fc1","type":"custom_tool_call","call_id":"new","name":"exec","input":"  text(\"é\");\r\n","status":"completed"}],"usage":{"output_tokens":3}}"#
                    .utf8))
        #expect(restored == expected)
        #expect(projection.originalBody == body)
    }

    @Test("Chat custom declarations, historical calls and new output are reversible")
    func chatRoundTrip() throws {
        let body = Data(
            #"""
            {
              "model": "m",
              "tools": [
                {
                  "type": "custom",
                  "custom": {
                    "name": "workspace__patch",
                    "format": {
                      "type": "text"
                    }
                  }
                }
              ],
              "tool_choice": {
                "type": "custom",
                "custom": {
                  "name": "workspace__patch"
                }
              },
              "messages": [
                {
                  "role": "assistant",
                  "tool_calls": [
                    {
                      "type": "custom",
                      "id": "old",
                      "custom": {
                        "name": "workspace__patch",
                        "input": ""
                      }
                    }
                  ]
                },
                {
                  "role": "tool",
                  "tool_call_id": "old",
                  "content": "done"
                }
              ]
            }
            """#.utf8)
        let projection = try CustomToolProjection.prepare(body: body, wire: .chatCompletions, adapt: true)
        let wire = try JSONValue.parse(projection.upstreamBody)
        #expect(wire["tools"]?[0]?["type"] == .string("function"))
        #expect(wire["tools"]?[0]?["function"]?["name"] == .string("workspace__patch"))
        #expect(
            wire["tool_choice"]
                == .object(["type": .string("function"), "function": .object(["name": .string("workspace__patch")])]))
        #expect(wire["messages"]?[0]?["tool_calls"]?[0]?["function"]?["arguments"] == .string(#"{"input":""}"#))
        let response = Data(
            #"""
            {
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "tool_calls": [
                      {
                        "type": "function",
                        "id": "new",
                        "function": {
                          "name": "workspace__patch",
                          "arguments": "{\"input\":\"a\\nb\"}"
                        }
                      }
                    ]
                  },
                  "finish_reason": "tool_calls"
                }
              ]
            }
            """#.utf8)
        let result = try JSONValue.parse(projection.restoreBuffered(response))
        #expect(
            result["choices"]?[0]?["message"]?["tool_calls"]?[0]
                == .object([
                    "type": .string("custom"), "id": .string("new"),
                    "custom": .object(["name": .string("workspace__patch"), "input": .string("a\nb")]),
                ]))
    }

    @Test("Retired names and genuine functions never become newly authorized custom calls")
    func currentDeclarationsOnly() throws {
        let body = Data(
            #"{"model":"m","tools":[{"type":"function","name":"exec","parameters":{}}],"input":[{"type":"custom_tool_call","call_id":"old","name":"retired","input":"x"}]}"#
                .utf8)
        let projection = try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true)
        let output = Data(
            #"{"output":[{"type":"function_call","call_id":"new","name":"exec","arguments":"{\"input\":\"x\"}"}]}"#.utf8
        )
        #expect(try projection.restoreBuffered(output) == output)
    }

    @Test("Malformed wrapped output is rejected rather than coercing or discarding bytes")
    func invalidEnvelope() throws {
        let body = Data(#"{"tools":[{"type":"custom","name":"exec"}],"input":"go"}"#.utf8)
        let projection = try CustomToolProjection.prepare(body: body, wire: .responses, adapt: true)
        for arguments in [#"{"input":"a","input":"b"}"#, #"{"input":null}"#, #"{"input":"x","extra":1}"#] {
            let response: JSONValue = .object([
                "output": .array([
                    .object([
                        "type": .string("function_call"), "name": .string("exec"),
                        "call_id": .string("new"), "arguments": .string(arguments),
                    ])
                ])
            ])
            #expect(throws: (any Swift.Error).self) {
                try projection.restoreBuffered(response.serializedData())
            }
        }
    }
}
