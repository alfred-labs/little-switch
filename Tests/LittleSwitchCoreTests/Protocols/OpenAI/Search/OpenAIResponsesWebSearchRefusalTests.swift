import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("Responses search refusal")
struct OpenAIResponsesWebSearchRefusalTests {
    @Test("Namespace tools adapt with refused or absent search", arguments: [false, true])
    func namespacesWithoutSearch(omitSearchTool: Bool) throws {
        let function: [String: Any] = [
            "type": "function", "name": "spawn_agent",
            "parameters": ["type": "object", "properties": [:]],
        ]
        let namespace: [String: Any] = [
            "type": "namespace", "name": "collaboration", "tools": [function],
        ]
        var tools = [namespace]
        if !omitSearchTool {
            tools.insert(["type": "web_search", "external_web_access": false], at: 0)
        }
        let body = try responseData(["model": "route", "input": "Call a tool.", "tools": tools])
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "upstream", configuration: .firecrawlCloud
            )
        )
        let upstream = try #require(
            JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
        var expectedFunction = function
        expectedFunction["name"] = "collaboration__spawn_agent"

        #expect(try responseData(upstream["tools"] as Any) == responseData([expectedFunction]))
        #expect(
            prepared.toolBindings == [
                "collaboration__spawn_agent": ResponsesToolNamespaces.Binding(
                    namespace: "collaboration", name: "spawn_agent"
                )
            ]
        )
        #expect(prepared.maximumUses == 0)
        #expect(prepared.searchOptions == WebSearchFilterOptions())
        #expect(prepared.originalBody == body)
        #expect(
            try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "upstream", configuration: .disabled
            )?.maximumUses == 0
        )
    }

    @Test("Owned history without search has no search budget", arguments: [false, true])
    func replayHasNoSearchBudget(refusedSearchTool: Bool) throws {
        let tools: [[String: Any]] =
            refusedSearchTool ? [["type": "web_search", "external_web_access": false]] : []
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: responseData([
                    "model": "route",
                    "input": [["type": "web_search_call", "id": "ws_previous"]],
                    "tools": tools,
                    "max_tool_calls": 1,
                ]),
                targetModel: "upstream",
                configuration: .firecrawlCloud
            )
        )

        #expect(prepared.maximumUses == 0)
    }

    @Test(
        "A refused search clears both forms of forced search choice",
        arguments: [
            #"{"type":"web_search"}"#,
            #"{"type":"function","name":"web_search"}"#,
        ]
    )
    func forcedSearchBecomesAuto(choiceJSON: String) throws {
        let upstream = try preparedReplay(choiceJSON: choiceJSON, tools: [weatherTool])

        #expect(try responseData(upstream["tools"] as Any) == responseData([weatherTool]))
        #expect(upstream["tool_choice"] as? String == "auto")
    }

    @Test(
        "Removing the last tool also removes every tool choice",
        arguments: [
            #"{"type":"web_search"}"#,
            #"{"type":"function","name":"web_search"}"#,
            #""required""#,
            #""auto""#,
            #""none""#,
        ]
    )
    func emptyToolsRemoveChoice(choiceJSON: String) throws {
        let upstream = try preparedReplay(choiceJSON: choiceJSON, tools: [])

        #expect((upstream["tools"] as? [Any])?.isEmpty == true)
        #expect(upstream["tool_choice"] == nil)
    }

    @Test(
        "Choices of remaining tools retain their complete value",
        arguments: [
            #"{"type":"function","name":"weather"}"#,
            #""required""#,
            #""auto""#,
            #""none""#,
        ]
    )
    func ordinaryChoicesSurvive(choiceJSON: String) throws {
        let upstream = try preparedReplay(choiceJSON: choiceJSON, tools: [weatherTool])
        let expected = try JSONSerialization.jsonObject(
            with: Data(choiceJSON.utf8), options: [.fragmentsAllowed]
        )

        #expect(try responseData(upstream["tool_choice"] as Any) == responseData(expected))
    }

    @Test("An absent choice is not invented")
    func absentChoiceStaysAbsent() throws {
        let upstream = try preparedReplay(choiceJSON: nil, tools: [weatherTool])

        #expect(upstream["tool_choice"] == nil)
    }

    @Test("Refusing external search preserves a forced MCP search choice")
    func namespacedSearchChoiceSurvives() throws {
        let remainingTools: [[String: Any]] = [
            [
                "type": "namespace", "name": "mcp",
                "tools": [["type": "function", "name": "web_search"]],
            ]
        ]

        let upstream = try preparedReplay(
            choiceJSON: #"{"type":"function","name":"web_search","namespace":"mcp"}"#,
            tools: remainingTools
        )
        let expected: [String: Any] = ["type": "function", "name": "mcp__web_search"]

        #expect(try responseData(upstream["tool_choice"] as Any) == responseData(expected))
    }

    private var weatherTool: [String: Any] {
        ["type": "function", "name": "weather", "parameters": ["type": "object"]]
    }

    private func preparedReplay(
        choiceJSON: String?, tools: [[String: Any]]
    ) throws -> [String: Any] {
        var request: [String: Any] = [
            "model": "route",
            "input": [
                ["type": "message", "role": "user", "content": "Continue."],
                ["type": "web_search_call", "id": "ws_previous", "status": "completed"],
            ],
            "tools": [["type": "web_search", "external_web_access": false]] + tools,
        ]
        if let choiceJSON {
            request["tool_choice"] = try JSONSerialization.jsonObject(
                with: Data(choiceJSON.utf8), options: [.fragmentsAllowed]
            )
        }
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: responseData(request),
                targetModel: "upstream",
                configuration: .firecrawlCloud
            )
        )
        return try #require(
            JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
    }
}
