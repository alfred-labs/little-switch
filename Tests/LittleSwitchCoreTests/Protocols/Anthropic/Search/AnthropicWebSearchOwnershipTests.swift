import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic web-search ownership")
struct AnthropicWebSearchOwnershipTests {
    @Test("An ordinary client tool named web_search does not engage the gateway bridge")
    func ordinaryClientTool() throws {
        for name in ["web_search", "web_search_lookup"] {
            let body = try ownershipSearchBody(tools: [ownershipClientTool(name)])
            for configuration in [WebSearchConfiguration.disabled, .firecrawlCloud] {
                #expect(
                    try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: configuration)
                        == nil
                )
            }
        }
    }

    @Test("A built-in search binding preserves a same-name client tool exactly")
    func collidingClientTool() throws {
        let client = ownershipClientTool("web_search")
        let body = try ownershipSearchBody(tools: [["type": "web_search_20250305"], client])
        let candidate = try AnthropicWebSearch.prepare(
            body: body, targetModel: "provider", configuration: .firecrawlCloud)
        let prepared = try #require(candidate)
        let tools = try #require(anthropicWebSearchObject(prepared.upstreamBody)["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["__little_switch_web_search", "web_search"])
        #expect(NSDictionary(dictionary: try #require(tools.last)).isEqual(to: client))
    }

    @Test("Declaration preparation without supplied history preserves the client catalog")
    func declarationsWithoutHistory() throws {
        let client = ownershipClientTool("web_search")
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "claude",
            "tools": [["type": "web_search_20250305"], client],
            "tool_choice": ["type": "web_search_20250305"],
        ])
        let candidate = try AnthropicWebSearch.prepare(
            body: body,
            targetModel: "provider",
            configuration: .firecrawlCloud
        )
        let prepared = try #require(candidate)
        let upstream = try anthropicWebSearchObject(prepared.upstreamBody)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        #expect(prepared.privateToolName == "__little_switch_web_search")
        #expect(tools.compactMap { $0["name"] as? String } == ["__little_switch_web_search", "web_search"])
        #expect(NSDictionary(dictionary: try #require(tools.last)).isEqual(to: client))
        #expect(upstream["tool_choice"] as? [String: String] == ["type": "tool", "name": "__little_switch_web_search"])
        #expect(upstream["messages"] == nil)
    }

    @Test("Private search names avoid both the current client catalog and retired historical tools")
    func privateNameCollisions() throws {
        let messages: [[String: Any]] = [
            [
                "role": "assistant",
                "content": [
                    ["type": "tool_use", "id": "retired", "name": "__little_switch_web_search_2", "input": [:]]
                ],
            ],
            [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result", "tool_use_id": "retired",
                        "content": [["type": "tool_reference", "tool_name": "__little_switch_web_search_3"]],
                    ]
                ],
            ],
        ]
        let body = try ownershipSearchBody(
            tools: [
                ["type": "web_search_20250305"], ownershipClientTool("web_search"),
                ownershipClientTool("__little_switch_web_search"),
            ],
            messages: messages,
            choice: ["type": "web_search_20250305"]
        )
        let candidate = try AnthropicWebSearch.prepare(
            body: body, targetModel: "provider", configuration: .firecrawlCloud)
        let prepared = try #require(candidate)
        let object = try anthropicWebSearchObject(prepared.upstreamBody)
        let tools = try #require(object["tools"] as? [[String: Any]])
        #expect(tools.first?["name"] as? String == "__little_switch_web_search_4")
        #expect(object["tool_choice"] as? [String: String] == ["type": "tool", "name": "__little_switch_web_search_4"])
        #expect(NSArray(array: try #require(object["messages"] as? [[String: Any]])).isEqual(to: messages))
    }

    @Test("A forced ordinary client search choice retains client ownership")
    func forcedClientSearch() throws {
        let choice = ["type": "tool", "name": "web_search"]
        let body = try ownershipSearchBody(
            tools: [["type": "web_search_20250305"], ownershipClientTool("web_search")], choice: choice
        )
        let candidate = try AnthropicWebSearch.prepare(
            body: body, targetModel: "provider", configuration: .firecrawlCloud)
        let prepared = try #require(candidate)
        #expect(try anthropicWebSearchObject(prepared.upstreamBody)["tool_choice"] as? [String: String] == choice)
    }

    @Test("Disabling search removes the native declaration and allows ordinary conversation")
    func disabledBuiltInSearch() throws {
        for clientTools in [[], [ownershipClientTool("web_search")]] {
            let body = try ownershipSearchBody(
                tools: [["type": "web_search_20250305"]] + clientTools,
                choice: ["type": "web_search_20250305"]
            )
            let candidate = try AnthropicWebSearch.prepare(
                body: body, targetModel: "provider", configuration: .disabled)
            let prepared = try #require(candidate)
            #expect(prepared.maximumUses == 0)
            #expect(prepared.privateToolName == nil)
            let object = try anthropicWebSearchObject(prepared.upstreamBody)
            let tools = try #require(object["tools"] as? [[String: Any]])
            #expect(NSArray(array: tools).isEqual(to: clientTools))
            if clientTools.isEmpty {
                #expect(object["tool_choice"] == nil)
            } else {
                #expect(object["tool_choice"] as? [String: String] == ["type": "auto"])
            }
        }
    }

    @Test("Unrecognized server-search types do not acquire gateway tool ownership by prefix")
    func unsupportedSearchTypes() throws {
        for type in ["web_search", "web_search_beta", "web_search_20990101", "web_search_lookup"] {
            let body = try ownershipSearchBody(tools: [["type": type]])
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: .firecrawlCloud)
            }
        }
    }

    @Test("Multiple native search declarations fail instead of silently dropping a policy")
    func duplicateSearchDeclarations() throws {
        let body = try ownershipSearchBody(tools: [["type": "web_search_20250305"], ["type": "web_search_20260209"]])
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: .firecrawlCloud)
        }
    }

    @Test("A selected bridge does not admit unrelated provider-hosted tool declarations")
    func hostedToolsBesideSearch() throws {
        let body = try ownershipSearchBody(
            tools: [["type": "web_search_20250305"], ["type": "web_fetch_20250910", "name": "web_fetch"]]
        )
        #expect(throws: (any Error).self) {
            try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: .firecrawlCloud)
        }
    }

    @Test("Unknown forced native-search choices fail before provider dispatch")
    func unsupportedForcedSearch() throws {
        let body = try ownershipSearchBody(
            tools: [["type": "web_search_20250305"]], choice: ["type": "web_search_beta"]
        )
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: .firecrawlCloud)
        }
    }

    @Test("Disabling the only declared tool removes an impossible any-tool choice")
    func disabledAnyChoice() throws {
        let body = try ownershipSearchBody(tools: [["type": "web_search_20250305"]], choice: ["type": "any"])
        let candidate = try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: .disabled)
        let prepared = try #require(candidate)
        #expect(try anthropicWebSearchObject(prepared.upstreamBody)["tool_choice"] == nil)
    }

    @Test("An eligible native-search request requires a nonempty client model")
    func invalidClientModel() throws {
        for model: Any in [NSNull(), "", 42] {
            let body = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": [["role": "user", "content": "Swift"]],
                "tools": [["type": "web_search_20250305"]],
            ])
            for configuration in [WebSearchConfiguration.disabled, .firecrawlCloud] {
                #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                    try AnthropicWebSearch.prepare(body: body, targetModel: "provider", configuration: configuration)
                }
            }
        }
    }
}

func ownershipClientTool(_ name: String) -> [String: Any] {
    ["name": name, "description": "Client owns this tool", "input_schema": ["type": "object", "properties": [:]]]
}

func ownershipSearchBody(
    tools: [[String: Any]],
    messages: [[String: Any]] = [],
    choice: [String: Any]? = nil
) throws -> Data {
    var object: [String: Any] = ["model": "claude", "messages": messages, "tools": tools]
    object["tool_choice"] = choice
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
