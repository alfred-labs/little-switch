import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Portable server-tool history")
struct PortableToolHistoryTests {
    @Test("Previously executed server tools become ordered readable history")
    func serverToolReplay() throws {
        let body = Data(
            #"""
            {
              "model": "old",
              "messages": [
                {"role": "user", "content": "Describe the image."},
                {
                  "role": "assistant",
                  "content": [
                    {"type": "text", "text": "Before"},
                    {"type": "server_tool_use", "id": "call_image", "name": "analyze_image", "input": {}},
                    {"type": "tool_result", "tool_use_id": "call_image", "content": "A red square."},
                    {"type": "text", "text": "After"}
                  ]
                }
              ]
            }
            """#.utf8
        )
        let expected = Data(
            #"""
            {
              "model": "new",
              "messages": [
                {"role": "user", "content": "Describe the image."},
                {
                  "role": "assistant",
                  "content": [
                    {"type": "text", "text": "Before"},
                    {"type": "text", "text": "[Previous server tool: analyze_image]\nInput: {}"},
                    {"type": "text", "text": "[Previous server tool result: analyze_image]\nA red square."},
                    {"type": "text", "text": "After"}
                  ]
                }
              ]
            }
            """#.utf8
        )
        let rewritten = try LiveGatewaySerializer().rewriteMessage(body, modelID: "new")
        #expect(try object(rewritten) == object(expected))
        #expect(
            try LiveGatewaySerializer().rewriteMessage(rewritten, modelID: "new") == rewritten
        )
    }

    @Test("Cross-message pairs preserve removed client tools and discovery references")
    func crossMessagePairs() throws {
        let body = Data(
            #"""
            {
              "model": "old",
              "tools": [],
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {"detail": "high"}},
                    {"type": "tool_use", "id": "client_1", "name": "old_client_tool", "input": {}}
                  ]
                },
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "tool_result",
                      "tool_use_id": "client_1",
                      "content": [
                        {"type": "text", "text": "<functions>definitions</functions>"},
                        {"type": "tool_reference", "tool_name": "old_client_tool"}
                      ]
                    }
                  ]
                },
                {
                  "role": "assistant",
                  "content": [
                    {
                      "type": "tool_result",
                      "tool_use_id": "srv_1",
                      "is_error": true,
                      "content": [{"type": "text", "text": "Image unavailable"}]
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let expected = Data(
            #"""
            {
              "model": "new",
              "tools": [],
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "text", "text": "[Previous server tool: analyze_image]\nInput: {\"detail\":\"high\"}"},
                    {"type": "tool_use", "id": "client_1", "name": "old_client_tool", "input": {}}
                  ]
                },
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "tool_result",
                      "tool_use_id": "client_1",
                      "content": [
                        {"type": "text", "text": "<functions>definitions</functions>"},
                        {"type": "tool_reference", "tool_name": "old_client_tool"}
                      ]
                    }
                  ]
                },
                {
                  "role": "assistant",
                  "content": [{"type": "text", "text": "[Previous server tool error: analyze_image]\nImage unavailable"}]
                }
              ]
            }
            """#.utf8
        )
        #expect(
            try object(LiveGatewaySerializer().rewriteMessage(body, modelID: "new"))
                == object(expected)
        )
    }

    @Test("Token counting receives the same portable history")
    func countTokensHistory() throws {
        let body = Data(
            #"""
            {
              "model": "new",
              "max_tokens": 32,
              "stream": true,
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
                    {"type": "tool_result", "tool_use_id": "srv_1", "content": "An image."}
                  ]
                }
              ]
            }
            """#.utf8
        )
        let projected = try AnthropicCountTokensRequest.project(body)
        let expected = Data(
            #"""
            {
              "model": "new",
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "text", "text": "[Previous server tool: analyze_image]\nInput: {}"},
                    {"type": "text", "text": "[Previous server tool result: analyze_image]\nAn image."}
                  ]
                }
              ]
            }
            """#.utf8
        )
        #expect(try object(projected) == object(expected))
    }

    @Test(
        "Ambiguous or incomplete server lifecycles fail without dropping history",
        arguments: [
            #"[{"type":"server_tool_use","id":"srv_1","name":"analyze_image","input":{}}]"#,
            #"""
            [
              {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
              {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
              {"type": "tool_result", "tool_use_id": "srv_1", "content": "value"}
            ]
            """#,
            #"""
            [
              {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
              {"type": "tool_use", "id": "srv_1", "name": "client", "input": {}},
              {"type": "tool_result", "tool_use_id": "srv_1", "content": "value"}
            ]
            """#,
            #"""
            [
              {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
              {"type": "tool_result", "tool_use_id": "srv_1", "content": "first"},
              {"type": "tool_result", "tool_use_id": "srv_1", "content": "second"}
            ]
            """#,
            #"[{"type":"server_tool_use","id":"","name":"analyze_image","input":{}},{"type":"tool_result","tool_use_id":"","content":"value"}]"#,
            #"[{"type":"server_tool_use","id":"srv_1","name":"analyze_image","input":null},{"type":"tool_result","tool_use_id":"srv_1","content":"value"}]"#,
            #"""
            [
              {"type": "server_tool_use", "id": "srv_1", "name": "analyze_image", "input": {}},
              {
                "type": "tool_result",
                "tool_use_id": "srv_1",
                "content": [{"type": "image", "source": {"type": "base64", "data": "opaque"}}]
              }
            ]
            """#,
        ]
    )
    func invalidServerHistory(_ content: String) throws {
        let body = Data(
            (#"{"model":"old","messages":[{"role":"assistant","content":"#
                + content + #"}]}"#).utf8
        )
        #expect(throws: (any Error).self) {
            try LiveGatewaySerializer().rewriteMessage(body, modelID: "new")
        }
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
