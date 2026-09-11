import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Legacy Ollama compaction import")
struct OllamaCompactionPayloadTests {
    @Test("Legacy messages, reasoning and paired calls expand without guessing a namespace")
    func messagesAndCalls() throws {
        let item = try legacy(retained: [
            ["role": "USER", "content": "Initial request"],
            [
                "role": "assistant", "content": "I will inspect.", "thinking": "Preserve this reasoning.",
                "tool_calls": [["id": "call", "function": ["name": "a.b.c", "arguments": ["path": "file"]]]],
            ],
            ["role": "tool", "tool_call_id": "call", "tool_name": "a.b.c", "content": "Read result"],
        ])
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        let expected: [[String: Any]] = [
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Legacy summary"]]],
            ["type": "message", "role": "user", "content": "Initial request"],
            [
                "type": "reasoning", "id": "rs_resp_0",
                "summary": [["type": "summary_text", "text": "Preserve this reasoning."]],
            ],
            ["type": "message", "role": "assistant", "content": "I will inspect."],
            ["type": "function_call", "call_id": "call", "name": "a.b.c", "arguments": #"{"path":"file"}"#],
            ["type": "function_call_output", "call_id": "call", "output": "Read result"],
        ]
        #expect(try ResponsesCompactionFixture.data(expanded) == ResponsesCompactionFixture.data(expected))
        #expect(try ResponsesCompactionFixture.plan(items: [item]).originalModel == "original-model")
    }

    @Test("Ambiguous wire spellings restore the exact standalone metadata pairs")
    func standaloneNames() throws {
        let item = try legacy(
            retained: [
                ["role": "tool", "tool_name": "a.b.c", "content": "first"],
                ["role": "tool", "tool_name": "a.b.c", "content": "second"],
                ["role": "tool", "tool_name": "a.b.c", "content": "third"],
            ],
            names: [
                "0": ["namespace": "a.b", "name": "c"], "1": ["namespace": "a", "name": "b.c"], "2": ["name": "a.b.c"],
            ]
        )
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        let expected: [[String: Any]] = [
            ["type": "function_call_output", "namespace": "a.b", "name": "c", "output": "first"],
            ["type": "function_call_output", "namespace": "a", "name": "b.c", "output": "second"],
            ["type": "function_call_output", "name": "a.b.c", "output": "third"],
        ]
        #expect(
            try ResponsesCompactionFixture.data(Array(expanded.dropFirst()))
                == ResponsesCompactionFixture.data(expected))
    }

    @Test(
        "Legacy namespace spelling is validated without rewriting the recorded pair",
        arguments: [
            ["workspace.read", "workspace.read"], ["workspace_read", "workspace_read"], ["_read", "workspace_read"],
            ["read", "workspace.read"],
        ])
    func legacySpelling(names: [String]) throws {
        let item = try legacy(
            retained: [["role": "tool", "tool_name": names[1], "content": "task"]],
            names: ["0": ["namespace": "workspace", "name": names[0]]]
        )
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        #expect(expanded.last?["namespace"] as? String == "workspace")
        #expect(expanded.last?["name"] as? String == names[0])
    }

    @Test("Client tool-search discovery remains native execution state")
    func search() throws {
        let tools: [[String: Any]] = [["type": "function", "name": "read", "parameters": ["type": "object"]]]
        let item = try legacy(retained: [
            [
                "role": "assistant",
                "tool_calls": [["id": "search", "function": ["name": "tool_search", "arguments": ["query": "read"]]]],
            ],
            [
                "role": "tool", "tool_call_id": "search", "tool_name": "tool_search",
                "content": try ResponsesCompactionFixture.text(tools),
            ],
        ])
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        #expect(expanded.count == 3)
        #expect(expanded[1]["type"] as? String == "tool_search_call")
        #expect(expanded[1]["arguments"] as? [String: String] == ["query": "read"])
        #expect(expanded[2]["type"] as? String == "tool_search_output")
        #expect(
            try ResponsesCompactionFixture.data(expanded[2]["tools"] as Any) == ResponsesCompactionFixture.data(tools))
    }

    @Test(
        "Legacy image bytes become real Responses image blocks",
        arguments: [
            [UInt8]([137, 80, 78, 71, 13, 10, 26, 10]), [255, 216, 255],
            [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80, 86, 80],
        ])
    func images(bytes: [UInt8]) throws {
        let encoded = Data(bytes).base64EncodedString()
        let item = try legacy(retained: [["role": "user", "content": "Picture", "images": [encoded]]])
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        let parts = try #require(expanded.last?["content"] as? [[String: Any]])
        #expect(parts.first?["type"] as? String == "input_text")
        #expect(parts.last?["type"] as? String == "input_image")
        #expect((parts.last?["image_url"] as? String)?.hasSuffix(encoded) == true)
        #expect(parts.last?["detail"] as? String == "auto")
        let imageOnly = try #require(
            try ResponsesCompactionPayload.expand(
                item: legacy(retained: [
                    [
                        "role": "user", "images": [encoded],
                    ]
                ])))
        #expect((imageOnly.last?["content"] as? [[String: Any]])?.count == 1)
    }

    @Test(
        "Malformed retained records fail instead of dropping context",
        arguments: [
            #"[{"role":"unknown","content":"text"}]"#,
            #"[{"role":"user","content":7}]"#,
            #"[{"role":"user","images":["not base64"]}]"#,
            #"[{"role":"user","images":[""]}]"#,
            #"[{"role":"user","images":["R0lGODlh"]}]"#,
            #"[{"role":"user","images":[null]}]"#,
            #"[{"role":"user","unknown_state":"must not disappear"}]"#,
            #"[{"role":"tool","content":"orphan"}]"#,
            #"[{"role":"assistant","tool_calls":7}]"#,
            #"[{"role":"assistant","tool_calls":[{}]}]"#,
            #"[{"role":"assistant","tool_calls":[{"id":"","function":{"name":"read","arguments":{}}}]}]"#,
            #"[{"role":"assistant","tool_calls":[{"id":"call","function":{"name":"","arguments":{}}}]}]"#,
            #"[{"role":"assistant","tool_calls":[{"id":"call","function":{"name":"read","arguments":"wrong"}}]}]"#,
            #"[{"role":"tool","tool_call_id":"search","tool_name":"tool_search","content":"not JSON"}]"#,
            #"[{"role":"tool","tool_call_id":"search","tool_name":"tool_search","content":"[]","images":["iVBORw0KGgo="]}]"#,
        ])
    func malformedRetained(json: String) throws {
        let retained = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(throws: ResponsesCompactionError.invalidPayload) {
            try ResponsesCompactionPayload.expand(item: legacy(retained: retained))
        }
    }

    @Test(
        "Standalone indexes and identities must match their retained message",
        arguments: [
            #"{"-1":{"namespace":"workspace","name":"handoff"}}"#,
            #"{"1":{"namespace":"workspace","name":"handoff"}}"#,
            #"{"01":{"namespace":"workspace","name":"handoff"}}"#,
            #"{"0":{"namespace":"workspace","name":"other"}}"#,
            #"{"0":{"namespace":"workspace","name":" "}}"#,
            #"{"0":{"namespace":7,"name":"handoff"}}"#,
            #"{"0":{"name":"handoff","extra":true}}"#,
        ])
    func invalidNames(json: String) throws {
        let names = try ResponsesCompactionFixture.object(Data(json.utf8))
        #expect(throws: ResponsesCompactionError.invalidPayload) {
            try ResponsesCompactionPayload.expand(
                item: legacy(
                    retained: [["role": "tool", "tool_name": "workspace.handoff", "content": "task"]], names: names))
        }
    }

    @Test("Legacy empty retained arrays and absent optional fields remain readable")
    func optionalFields() throws {
        let nulls: [String: Any] = [
            "role": "assistant", "content": NSNull(), "thinking": NSNull(), "images": NSNull(),
            "tool_calls": NSNull(), "tool_name": NSNull(), "tool_call_id": NSNull(),
        ]
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: legacy(retained: [nulls])))
        #expect((expanded.last?["content"] as? String)?.isEmpty == true)
        #expect(try ResponsesCompactionPayload.expand(item: legacy(retained: []))?.count == 1)
        let emptyArguments = try legacy(retained: [
            [
                "role": "assistant", "tool_calls": [["id": "call", "function": ["name": "read"]]],
            ]
        ])
        #expect(try ResponsesCompactionPayload.expand(item: emptyArguments)?.last?["arguments"] as? String == "{}")
    }

    @Test(
        "Malformed legacy payload headers and metadata are rejected",
        arguments: [
            #"{"type":"ollama_compaction","version":2,"summary":"s","retained":[]}"#,
            #"{"type":"ollama_compaction","version":true,"summary":"s","retained":[]}"#,
            #"{"type":"ollama_compaction","version":1,"summary":" ","retained":[]}"#,
            #"{"type":"ollama_compaction","version":1,"summary":"s","retained":[null]}"#,
            #"{"type":"ollama_compaction","version":1,"summary":"s","retained":[],"extra":true}"#,
            #"{"type":"ollama_compaction","version":1,"summary":"s","retained":[],"standalone_names":[]}"#,
            #"{"type":"ollama_compaction","version":1,"summary":"s","retained":[{"role":"user","tool_name":"read"}],"standalone_names":{"0":{"name":"read"}}}"#,
            #"{"type":"ollama_compaction","version":1,"summary":"s","retained":[{"role":"tool","tool_call_id":"call","tool_name":"read"}],"standalone_names":{"0":{"name":"read"}}}"#,
        ])
    func invalidPayload(json: String) {
        #expect(throws: ResponsesCompactionError.invalidPayload) {
            try ResponsesCompactionPayload.expand(item: ["type": "compaction", "encrypted_content": json])
        }
    }

    private func legacy(retained: [[String: Any]], names: [String: Any]? = nil) throws -> [String: Any] {
        var payload: [String: Any] = [
            "type": "ollama_compaction", "version": 1, "summary": "Legacy summary", "retained": retained,
        ]
        if let names { payload["standalone_names"] = names }
        return ["type": "compaction", "encrypted_content": try ResponsesCompactionFixture.text(payload)]
    }
}
