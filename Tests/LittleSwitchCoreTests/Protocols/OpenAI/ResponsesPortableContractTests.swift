import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Responses portable gateway contract")
struct ResponsesPortableContractTests {
    @Test(
        "Hosted provider declarations require an explicit gateway adapter",
        arguments: ["tool_search", "file_search", "web_search_invalid"])
    func rejectsHostedTools(type: String) {
        #expect(throws: (any Error).self) {
            try prepare(tools: [["type": type]])
        }
    }
    @Test("Search binding preserves a client function with the same name")
    func searchNameCollision() throws {
        let prepared = try #require(
            try prepare(tools: [
                ["type": "web_search"],
                ["type": "function", "name": "web_search", "parameters": ["type": "object"]],
            ])
        )
        let root = try object(prepared.upstreamBody)
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 2)
        #expect(Set(tools.compactMap { $0["name"] as? String }).count == 2)
        #expect(tools.contains { $0["name"] as? String == "web_search" })
    }

    @Test("Search-disabled requests cannot outsource built-in tools")
    func unavailableSearch() throws {
        let prepared = try #require(try prepare(tools: [["type": "web_search"]], configuration: .disabled))
        #expect(prepared.maximumUses == 0)
        #expect(prepared.privateToolName == nil)
        #expect((try object(prepared.upstreamBody)["tools"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("Published preview variants use the gateway bridge")
    func previewSearch() throws {
        for type in ["web_search_preview", "web_search_preview_2025_03_11"] {
            #expect(try prepare(tools: [["type": type]]) != nil)
        }
    }

    @Test("Namespace and client discovery adaptation work without web search")
    func independentAdapters() throws {
        for tools: [[String: Any]] in [
            [
                [
                    "type": "namespace", "name": "files",
                    "tools": [
                        ["type": "function", "name": "read", "parameters": ["type": "object"]]
                    ],
                ]
            ],
            [
                [
                    "type": "tool_search", "execution": "client", "description": "Find tools",
                    "parameters": ["type": "object"],
                ]
            ],
        ] {
            let prepared = try #require(try prepare(tools: tools, configuration: .disabled))
            #expect(prepared.maximumUses == 0)
            let upstream = try object(prepared.upstreamBody)
            let wireTools = try #require(upstream["tools"] as? [[String: Any]])
            #expect(wireTools.allSatisfy { $0["type"] as? String == "function" })
        }
    }

    @Test("Historical search actions remain readable on every provider wire")
    func searchHistory() throws {
        let input: [[String: Any]] = [
            [
                "type": "web_search_call", "id": "ws_old", "status": "completed",
                "action": [
                    "type": "search", "query": "Swift",
                    "sources": [
                        ["type": "url", "url": "https://swift.org"]
                    ],
                ],
            ],
            ["type": "message", "role": "user", "content": "Summarize the previous search."],
        ]
        let body = try JSONSerialization.data(withJSONObject: ["model": "slug", "input": input])
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let text = try #require(String(bytes: normalized.body, encoding: .utf8))
        #expect(text.contains("https://swift.org"))
        #expect(text.contains("Swift"))
        let chat = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "upstream")
        let chatText = try #require(String(bytes: chat.upstreamBody, encoding: .utf8))
        #expect(chatText.contains("https://swift.org"))
        #expect(chatText.contains("Swift"))
    }

    @Test("An ordinary web_search function remains public when no search is enabled")
    func ordinarySearchFunction() throws {
        let prepared = try #require(
            try prepare(tools: [
                ["type": "namespace", "name": "files", "tools": []],
                ["type": "function", "name": "web_search", "parameters": ["type": "object"]],
            ])
        )
        let upstream = try object(prepared.upstreamBody)
        #expect((upstream["tools"] as? [[String: Any]])?.count == 1)
        let response = Data(
            #"""
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "web_search",
                  "arguments": "{}",
                  "status": "completed"
                }
              ],
              "usage": {
                "input_tokens": 1,
                "output_tokens": 1
              }
            }
            """#.utf8
        )
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(response)
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared, traces: [], finalTurn: turn, usage: turn.usage
        )
        #expect((try object(projected)["output"] as? [[String: Any]])?.count == 1)
    }

    private func prepare(
        tools: [[String: Any]],
        configuration: WebSearchConfiguration = .firecrawlCloud
    ) throws -> PreparedResponsesWebSearchRequest? {
        try OpenAIResponsesWebSearch.prepare(
            body: JSONSerialization.data(withJSONObject: ["model": "slug", "input": "Hello", "tools": tools]),
            targetModel: "upstream",
            configuration: configuration
        )
    }

    private func object(_ body: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
