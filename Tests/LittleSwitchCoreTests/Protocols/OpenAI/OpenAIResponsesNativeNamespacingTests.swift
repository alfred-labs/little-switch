import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses native namespacing")
struct OpenAIResponsesNativeNamespacingTests {
    private func requestBody(
        input: [Any],
        tools: [Any]
    ) throws -> Data {
        try responseData([
            "model": "little-switch-route",
            "input": input,
            "tools": tools,
            "stream": true,
        ])
    }

    @Test("Namespace specs flatten and history calls lose their namespace")
    func flattensToolsAndHistory() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try requestBody(
                input: [
                    [
                        "type": "message",
                        "role": "user",
                        "content": [["type": "input_text", "text": "Spawn one."]],
                    ],
                    [
                        "type": "function_call",
                        "call_id": "call_1",
                        "name": "spawn_agent",
                        "namespace": "collaboration",
                        "arguments": #"{"message":"Go"}"#,
                    ],
                    [
                        "type": "function_call_output",
                        "call_id": "call_1",
                        "output": "ok",
                    ],
                ],
                tools: [
                    [
                        "type": "web_search"
                    ],
                    [
                        "type": "namespace",
                        "name": "collaboration",
                        "description": "Collab.",
                        "tools": [
                            [
                                "type": "function",
                                "name": "spawn_agent",
                                "description": "Spawn one.",
                                "parameters": ["type": "object", "properties": [:]],
                            ]
                        ],
                    ],
                ]
            )
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let tools = try #require(object["tools"] as? [[String: Any]])
        let names = tools.compactMap { tool -> String? in
            guard tool["type"] as? String == "function" else {
                return nil
            }
            return tool["name"] as? String
        }
        #expect(names == ["collaboration__spawn_agent"])
        let items = try #require(object["input"] as? [[String: Any]])
        let call = try #require(items.first { $0["type"] as? String == "function_call" })
        #expect(call["name"] as? String == "collaboration__spawn_agent")
        #expect(call["namespace"] == nil)
        #expect(normalized.toolBindings["collaboration__spawn_agent"] != nil)
    }

    @Test("Agent mail converts into a plain user message with its brief")
    func convertsAgentMail() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try requestBody(
                input: [
                    [
                        "type": "agent_message",
                        "id": "amsg_1",
                        "author": "/root",
                        "recipient": "/root/prenom_1",
                        "content": [
                            [
                                "type": "input_text",
                                "text": "Message Type: NEW_TASK\nPayload:\n",
                            ],
                            [
                                "type": "encrypted_content",
                                "encrypted_content": "Invente un prénom.",
                            ],
                        ],
                    ],
                    [
                        "type": "agent_message",
                        "id": "amsg_2",
                        "author": "/root",
                        "recipient": "/root/prenom_2",
                        "content": [["type": "input_text", "text": ""]],
                    ],
                ],
                tools: [["type": "web_search"]]
            )
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        #expect(items.count == 1)
        let message = try #require(items.first)
        #expect(message["type"] as? String == "message")
        #expect(message["role"] as? String == "user")
        let parts = try #require(message["content"] as? [[String: Any]])
        let text = try #require(parts.first?["text"] as? String)
        #expect(text.contains("Message Type: NEW_TASK"))
        #expect(text.contains("Invente un prénom."))
        #expect(normalized.toolBindings.isEmpty)
        #expect(normalized.droppedMailCount == 1)
    }

    @Test("A malformed namespace spec never reaches the provider")
    func dropsMalformedNamespaceSpecs() throws {
        let original = try requestBody(
            input: [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Hello."]],
                ]
            ],
            tools: [
                ["type": "web_search"],
                ["type": "namespace", "tools": [["type": "function", "name": "orphan"]]],
            ]
        )

        let normalized = try OpenAIResponsesNativeNamespacing.normalize(original)
        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let types = (object["tools"] as? [[String: Any]])?
            .compactMap { $0["type"] as? String }
        #expect(types == ["web_search"])
        #expect(normalized.toolBindings.isEmpty)
        #expect(normalized.droppedMailCount == 0)
        #expect(normalized.body != original)
    }

    @Test("Active native custom tool history retains structured exchanges")
    func convertsCustomToolHistory() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try requestBody(
                input: [
                    [
                        "type": "message",
                        "role": "user",
                        "content": [["type": "input_text", "text": "Run it."]],
                    ],
                    [
                        "type": "custom_tool_call",
                        "call_id": "call_9",
                        "name": "node_repl",
                        "input": "console.log('hi')",
                    ],
                    [
                        "type": "custom_tool_call_output",
                        "call_id": "call_9",
                        "output": "hi",
                    ],
                ],
                tools: [["type": "web_search"], ["type": "custom", "name": "node_repl"]]
            )
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        let types = items.compactMap { $0["type"] as? String }
        #expect(types == ["message", "custom_tool_call", "custom_tool_call_output"])
        #expect(
            items[1] as? [String: String] == [
                "type": "custom_tool_call", "call_id": "call_9", "name": "node_repl", "input": "console.log('hi')",
            ])
        #expect(
            items[2] as? [String: String] == ["type": "custom_tool_call_output", "call_id": "call_9", "output": "hi"])
    }

    @Test("Bodies without namespaces or mail stay byte-identical")
    func leavesPlainBodiesUntouched() throws {
        let body = try requestBody(
            input: [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Hello."]],
                ],
                [
                    "type": "function_call",
                    "call_id": "call_plain",
                    "name": "read_file",
                    "arguments": #"{"path":"README.md"}"#,
                ],
            ],
            tools: [["type": "web_search"]]
        )

        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        #expect(normalized.body == body)
        #expect(normalized.toolBindings.isEmpty)
    }

    @Test("Non-object bodies are rejected")
    func rejectsNonObjectBodies() {
        #expect(throws: OpenAIResponsesWebSearch.Error.self) {
            _ = try OpenAIResponsesNativeNamespacing.normalize(Data("[1,2]".utf8))
        }
    }

    @Test("The bridge carries flattened bindings alongside its prepared request")
    func bridgePrepareCarriesBindings() throws {
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: try requestBody(
                    input: [
                        [
                            "type": "message",
                            "role": "user",
                            "content": [["type": "input_text", "text": "Spawn one."]],
                        ]
                    ],
                    tools: [
                        ["type": "web_search"],
                        [
                            "type": "namespace",
                            "name": "collaboration",
                            "tools": [
                                [
                                    "type": "function",
                                    "name": "wait_agent",
                                    "parameters": ["type": "object", "properties": [:]],
                                ]
                            ],
                        ],
                    ]
                ),
                targetModel: "provider-model",
                configuration: WebSearchConfiguration()
            )
        )
        #expect(prepared.toolBindings["collaboration__wait_agent"] != nil)
        let upstream = try #require(
            try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
        let names = (upstream["tools"] as? [[String: Any]])?
            .compactMap { tool -> String? in
                guard tool["type"] as? String == "function" else {
                    return nil
                }
                return tool["name"] as? String
            }
        #expect(names == ["web_search", "collaboration__wait_agent"])
    }

}
