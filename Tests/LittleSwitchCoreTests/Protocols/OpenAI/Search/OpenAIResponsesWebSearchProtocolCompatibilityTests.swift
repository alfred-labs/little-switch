import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses web search protocol compatibility")
struct ResponsesSearchProtocolTests {
    @Test("A hosted search choice follows the private function through the Chat adapter")
    func hostedSearchToolChoice() throws {
        let body = Data(
            #"{"model":"slug","input":"latest","tools":[{"type":"web_search"}],"tool_choice":{"type":"web_search"}}"#
                .utf8
        )
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "glm-5.3",
                configuration: .firecrawlCloud
            )
        )
        let upstream = try protocolResponsesObject(prepared.upstreamBody)
        #expect(
            upstream["tool_choice"] as? [String: String]
                == ["type": "function", "name": "web_search"]
        )

        let adapted = try OpenAIResponsesChatCompletions.prepare(
            body: prepared.upstreamBody,
            targetModel: "glm-5.3"
        )
        let chat = try protocolResponsesObject(adapted.upstreamBody)
        let choice = try #require(chat["tool_choice"] as? [String: Any])
        #expect(choice["type"] as? String == "function")
        #expect(
            (choice["function"] as? [String: String])?["name"]
                == "web_search"
        )
    }

    @Test("The client max_tool_calls tightens the Firecrawl search bound")
    func clientMaximumToolCalls() throws {
        for (requested, expected) in [(1, 1), (5, 3)] {
            let body = try JSONSerialization.data(
                withJSONObject: [
                    "model": "slug",
                    "input": "latest",
                    "tools": [["type": "web_search"]],
                    "max_tool_calls": requested,
                ]
            )
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: body,
                    targetModel: "glm",
                    configuration: WebSearchConfiguration(maximumUses: 3)
                )
            )
            #expect(prepared.maximumUses == expected)
        }

        for invalid: Any in [0, "one"] {
            let body = try JSONSerialization.data(
                withJSONObject: [
                    "model": "slug",
                    "input": "latest",
                    "tools": [["type": "web_search"]],
                    "max_tool_calls": invalid,
                ]
            )
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                try OpenAIResponsesWebSearch.prepare(
                    body: body,
                    targetModel: "glm",
                    configuration: WebSearchConfiguration(maximumUses: 3)
                )
            }
        }
    }

    @Test("Terminal search errors remove impossible Responses tool choices")
    func terminalErrorResponsesToolChoice() throws {
        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            Data(
                #"{"id":"resp","output":[{"id":"fc","type":"function_call","name":"web_search","call_id":"call","arguments":"{}"}],"usage":{}}"#
                    .utf8
            )
        )
        let call = try #require(turn.webSearchCall)

        let forcedBody = try JSONSerialization.data(
            withJSONObject: [
                "model": "slug",
                "input": "latest",
                "tools": [
                    ["type": "web_search"],
                    ["type": "function", "name": "weather", "parameters": ["type": "object"]],
                ],
                "tool_choice": ["type": "web_search"],
            ]
        )
        let forcedPrepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: forcedBody,
                targetModel: "glm",
                configuration: .firecrawlCloud
            )
        )
        let forced = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: forcedPrepared.upstreamBody,
            turn: turn,
            toolCall: call,
            resultText: "unavailable",
            mode: .terminalError
        )
        let forcedObject = try protocolResponsesObject(forced)
        #expect(forcedObject["tool_choice"] as? String == "auto")
        #expect(
            (forcedObject["tools"] as? [[String: Any]])?.compactMap {
                $0["name"] as? String
            } == ["weather"]
        )

        let requiredBody = Data(
            #"{"model":"slug","input":"latest","tools":[{"type":"web_search"}],"tool_choice":"required"}"#
                .utf8
        )
        let requiredPrepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: requiredBody,
                targetModel: "glm",
                configuration: .firecrawlCloud
            )
        )
        let required = try OpenAIResponsesWebSearch.followUpRequest(
            baseBody: requiredPrepared.upstreamBody,
            turn: turn,
            toolCall: call,
            resultText: "unavailable",
            mode: .terminalError
        )
        let requiredObject = try protocolResponsesObject(required)
        #expect(requiredObject["tools"] == nil)
        #expect(requiredObject["tool_choice"] == nil)
    }
}

private func protocolResponsesObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
