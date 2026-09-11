import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses allowed tool choice parity")
struct ResponsesAllowedToolChoiceParityTests {
    @Test(
        "Chat allowed-tools choices retain the permitted subset and mode",
        arguments: ["auto", "required"])
    func chatAllowedChoice(mode: String) throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: request(mode: mode),
            targetModel: "upstream")
        let upstream = try chatJSONObject(prepared.upstreamBody)
        let wireName = try namespaceWireName(prepared.toolBindings)
        #expect(upstream["tool_choice"] as? String == mode)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        #expect(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String } == ["run", wireName])

        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: chatJSONData(["choices": [["finish_reason": "stop", "message": ["content": "Done"]]]]),
            prepared: prepared)
        #expect(
            try chatJSONObject(projected)["tool_choice"] as? NSDictionary == originalChoice(mode: mode) as NSDictionary)
    }

    @Test(
        "Native allowed-tools declarations retain the collision-safe permitted subset",
        arguments: ["auto", "required"])
    func nativeAllowedChoice(mode: String) throws {
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: request(mode: mode),
                targetModel: "upstream",
                configuration: .firecrawlCloud))
        let wireName = try namespaceWireName(prepared.toolBindings)
        let upstream = try chatJSONObject(prepared.upstreamBody)
        #expect(upstream["tool_choice"] as? String == mode)
        let tools = try #require(upstream["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["run", wireName])

        let turn = try OpenAIResponsesWebSearch.parseModelTurn(
            responseData(
                responseObject(
                    id: "resp_choice",
                    createdAt: 1,
                    status: "completed",
                    output: [],
                    usage: ResponsesUsage(
                        inputTokens: 1,
                        outputTokens: 1))))
        let projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: turn,
            usage: ResponsesUsage(
                inputTokens: 1,
                outputTokens: 1))
        #expect(
            try chatJSONObject(projected)["tool_choice"] as? NSDictionary == originalChoice(mode: mode) as NSDictionary)
    }

    @Test("A function without parameters and its forced selection survive Chat conversion")
    func parameterlessFunction() throws {
        let body = try chatJSONData([
            "model": "client", "input": "Ping.",
            "tools": [["type": "function", "name": "ping", "description": "No arguments."]],
            "tool_choice": ["type": "function", "name": "ping"],
        ])
        let native = try OpenAIResponsesNativeNamespacing.normalize(body)
        #expect(native.body == body)
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: body,
            targetModel: "upstream")
        let upstream = try chatJSONObject(prepared.upstreamBody)
        #expect(
            upstream["tools"] as? NSArray == [
                ["type": "function", "function": ["name": "ping", "description": "No arguments."]]
            ] as NSArray)
        #expect(
            upstream["tool_choice"] as? NSDictionary == [
                "type": "function", "function": ["name": "ping"],
            ] as NSDictionary)
    }

    private func request(mode: String) throws -> Data {
        let function: [String: Any] = ["type": "function", "name": "run", "parameters": ["type": "object"]]
        return try chatJSONData([
            "model": "client", "input": "Run the permitted task.",
            "tools": [
                function,
                ["type": "function", "name": "workspace__run", "parameters": ["type": "object"]],
                ["type": "namespace", "name": "workspace", "tools": [function]],
            ],
            "tool_choice": originalChoice(mode: mode),
        ])
    }

    private func originalChoice(mode: String) -> [String: Any] {
        [
            "type": "allowed_tools", "mode": mode,
            "tools": [
                ["type": "function", "name": "run"], ["type": "function", "namespace": "workspace", "name": "run"],
            ],
        ]
    }

    private func namespaceWireName(_ bindings: [String: ResponsesToolNamespaces.Binding]) throws -> String {
        try #require(
            bindings.first {
                $0.value
                    == .init(
                        namespace: "workspace",
                        name: "run")
            }?.key)
    }
}
