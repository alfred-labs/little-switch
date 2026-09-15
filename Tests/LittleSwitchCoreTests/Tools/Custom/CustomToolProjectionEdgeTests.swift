import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Custom projection identities and round trips")
struct CustomToolProjectionEdgeTests {
    @Test("Same-leaf namespaces and allowed selection have an exact inverse")
    func namespaceSelection() throws {
        let request = Data(
            #"""
            {
              "tools": [
                {
                  "type": "namespace",
                  "name": "a",
                  "tools": [
                    {
                      "type": "custom",
                      "name": "exec",
                      "format": {
                        "type": "text"
                      }
                    }
                  ]
                },
                {
                  "type": "namespace",
                  "name": "b",
                  "tools": [
                    {
                      "type": "custom",
                      "name": "exec"
                    }
                  ]
                }
              ],
              "tool_choice": {
                "type": "allowed_tools",
                "mode": "required",
                "tools": [
                  {
                    "type": "custom",
                    "name": "exec",
                    "namespace": "a"
                  }
                ]
              }
            }
            """#.utf8)
        let projection = try CustomToolProjection.prepare(body: request, wire: .responses, adapt: true)
        let root = try JSONValue.parse(projection.upstreamBody)
        #expect(root.object?["tool_choice"]?.object?["tools"]?.array?.first?.object?["type"] == .string("function"))
        #expect(projection.adapts(.object(["name": .string("exec"), "namespace": .string("a")])))
        #expect(!projection.adapts(.object(["name": .string("exec"), "namespace": .string("b")])))
        #expect(!projection.adapts(.object(["name": .string("a.exec")])))
    }

    @Test("Two response/replay cycles preserve every custom input byte", arguments: [false, true])
    func twoCycles(chat: Bool) throws {
        let inputs = ["", " text(\"é\");\r\n", "e\u{301} 🐈\u{0}"]
        let wire: ProviderToolContract.Wire = chat ? .chatCompletions : .responses
        var history: [JSONValue] = []
        for input in inputs {
            let tool: JSONValue =
                chat
                ? .object(["type": .string("custom"), "custom": .object(["name": .string("exec")])])
                : .object(["type": .string("custom"), "name": .string("exec")])
            let request: JSONValue = .object(["tools": .array([tool]), chat ? "messages" : "input": .array(history)])
            let projection = try CustomToolProjection.prepare(body: request.serializedData(), wire: wire, adapt: true)
            let arguments = try CustomToolInputEnvelope.encode(input)
            let call: JSONValue =
                chat
                ? .object([
                    "id": .string("call"), "type": .string("function"),
                    "function": .object(["name": .string("exec"), "arguments": .string(arguments)]),
                ])
                : .object([
                    "call_id": .string("call"), "type": .string("function_call"), "name": .string("exec"),
                    "arguments": .string(arguments),
                ])
            let response: JSONValue =
                chat
                ? .object([
                    "choices": .array([
                        .object(["message": .object(["role": .string("assistant"), "tool_calls": .array([call])])])
                    ])
                ])
                : .object(["output": .array([call])])
            let restored = try projection.restore(response)
            let restoredCall: JSONValue?
            if chat {
                let message = restored.object?["choices"]?.array?.first?.object?["message"]
                restoredCall = message?.object?["tool_calls"]?.array?.first
                history = [try #require(message)]
            } else {
                restoredCall = restored.object?["output"]?.array?.first
                history = [try #require(restoredCall)]
            }
            let roundTrip =
                chat
                ? restoredCall?.object?["custom"]?.object?["input"]?.string : restoredCall?.object?["input"]?.string
            #expect(Array(try #require(roundTrip).utf8) == Array(input.utf8))
        }
    }

    @Test("Responses echo metadata restores original custom declarations and selector")
    func responseMetadata() throws {
        let request = Data(
            #"""
            {
              "tools": [
                {
                  "type": "custom",
                  "name": "exec",
                  "description": "Run code",
                  "format": {
                    "type": "grammar",
                    "syntax": "lark",
                    "definition": "start: /.+/"
                  }
                }
              ],
              "tool_choice": {
                "type": "custom",
                "name": "exec"
              }
            }
            """#.utf8)
        let projection = try CustomToolProjection.prepare(body: request, wire: .responses, adapt: true)
        var echo = try #require(JSONValue.parse(projection.upstreamBody).object)
        echo["output"] = .array([])
        let restored = try projection.restore(.object(echo))
        let original = try JSONValue.parse(request)
        #expect(restored.object?["tools"] == original.object?["tools"])
        #expect(restored.object?["tool_choice"] == original.object?["tool_choice"])
    }
}
