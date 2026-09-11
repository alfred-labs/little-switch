import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Adapter namespace collision history")
struct NamespaceCollisionHistoryTests {
    private struct PreparedIdentityRequest {
        let body: Data
        let bindings: [String: ResponsesToolNamespaces.Binding]
        let declaredBindings: [String: ResponsesToolNamespaces.Binding]
    }

    @Test(
        "Colliding identities round trip through reordered declarations and repeated history",
        arguments: [
            ProviderToolContract.Wire.responses, .chatCompletions,
        ])
    func repeatedCollisionHistory(wire: ProviderToolContract.Wire) throws {
        var history: [[String: Any]] = [["type": "message", "role": "user", "content": "Read the files."]]
        for round in 0..<4 {
            var tools = declarations()
            if round > 0 { tools.removeLast() }
            if !round.isMultiple(of: 2) { tools.reverse() }
            let body = try chatJSONData(["model": "client-model", "input": history, "tools": tools])
            let prepared = try prepare(body, wire: wire)
            let upstream = try chatJSONObject(prepared.body)
            let providerTools = try #require(upstream["tools"] as? [[String: Any]])
            let wireNames = try providerTools.map { tool in
                let function = wire == .chatCompletions ? tool["function"] as? [String: Any] : tool
                return try #require(function?["name"] as? String)
            }
            #expect(Set(wireNames).count == expectedIdentities(tools).count)
            #expect(wireNames.allSatisfy { $0.count <= ResponsesToolNamespaces.maximumNameLength })
            try verifyHistory(history, upstream: upstream, bindings: prepared.bindings, wire: wire)

            let calls = wireNames.enumerated().map { index, name in
                functionCallItem(
                    id: "fc_\(round)_\(index)",
                    callID: "call_\(round)_\(index)",
                    name: name,
                    arguments: "{}",
                    status: "completed"
                )
            }
            let providerBody = try providerResponse(calls, wire: wire)
            let contract = try ProviderToolContract(
                wire: wire, requestBody: prepared.body, declaredToolBindings: prepared.declaredBindings
            )
            try contract.validateBuffered(providerBody)
            let output = try projectedOutput(body: body, providerBody: providerBody, wire: wire)
            #expect(output.map(identity) == expectedIdentities(tools))

            if round > 0 {
                let retired = ResponsesToolNamespaces.Binding(namespace: "retired", name: "read_file")
                let retiredWire = try #require(prepared.bindings.first { $0.value == retired }?.key)
                let retiredCall = functionCallItem(
                    id: "fc_retired", callID: "call_retired", name: retiredWire, arguments: "{}", status: "completed"
                )
                #expect(throws: ProviderToolContract.Error.undeclaredTool) {
                    try contract.validateBuffered(providerResponse([retiredCall], wire: wire))
                }
            }

            for item in output {
                history.append(item)
                history.append(["type": "function_call_output", "call_id": item["call_id"] as Any, "output": "ok"])
            }
        }
    }

    private func declarations() -> [[String: Any]] {
        [
            function("read_file"),
            namespace("workspace", ["read_file"]),
            function("a__b__c"),
            namespace("a__b", ["c"]),
            namespace("a", ["b__c", "_b", "a_b"]),
            namespace(String(repeating: "n", count: 40), [String(repeating: "t", count: 40)]),
            namespace("retired", ["read_file"]),
        ]
    }

    private func function(_ name: String) -> [String: Any] {
        ["type": "function", "name": name, "parameters": ["type": "object"]]
    }

    private func namespace(_ name: String, _ children: [String]) -> [String: Any] {
        ["type": "namespace", "name": name, "tools": children.map(function)]
    }

    private func expectedIdentities(_ tools: [[String: Any]]) -> [[String: String]] {
        tools.flatMap { tool in
            guard let children = tool["tools"] as? [[String: Any]], let namespace = tool["name"] as? String else {
                return [identity(tool)]
            }
            return children.map { child in
                var child = identity(child)
                child["namespace"] = namespace
                return child
            }
        }
    }

    private func identity(_ item: [String: Any]) -> [String: String] {
        item.filter { ["name", "namespace"].contains($0.key) }.compactMapValues { $0 as? String }
    }

    private func prepare(_ body: Data, wire: ProviderToolContract.Wire) throws -> PreparedIdentityRequest {
        if wire == .chatCompletions {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "upstream")
            return PreparedIdentityRequest(
                body: prepared.upstreamBody,
                bindings: prepared.toolBindings,
                declaredBindings: prepared.declaredToolBindings
            )
        }
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body, targetModel: "upstream", configuration: .firecrawlCloud
            ))
        return PreparedIdentityRequest(
            body: prepared.upstreamBody,
            bindings: prepared.toolBindings,
            declaredBindings: prepared.declaredToolBindings
        )
    }

    private func providerResponse(_ calls: [[String: Any]], wire: ProviderToolContract.Wire) throws -> Data {
        if wire == .chatCompletions {
            return try chatJSONData([
                "choices": [
                    [
                        "finish_reason": "tool_calls",
                        "message": [
                            "tool_calls": calls.map { call in
                                [
                                    "id": call["call_id"] as Any, "type": "function",
                                    "function": ["name": call["name"] as Any, "arguments": "{}"],
                                ]
                            }
                        ],
                    ]
                ]
            ])
        }
        return try responseData(
            responseObject(
                id: "resp_roundtrip",
                createdAt: 1,
                status: "completed",
                output: calls,
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            ))
    }

    private func projectedOutput(
        body: Data,
        providerBody: Data,
        wire: ProviderToolContract.Wire
    ) throws -> [[String: Any]] {
        let projected: Data
        if wire == .chatCompletions {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "upstream")
            projected = try OpenAIResponsesChatCompletions.project(responseBody: providerBody, prepared: prepared)
        } else {
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: body, targetModel: "upstream", configuration: .firecrawlCloud
                ))
            projected = try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared,
                traces: [],
                finalTurn: OpenAIResponsesWebSearch.parseModelTurn(providerBody),
                usage: ResponsesUsage(inputTokens: 0, outputTokens: 0)
            )
        }
        return try #require(chatJSONObject(projected)["output"] as? [[String: Any]])
    }

    private func verifyHistory(
        _ history: [[String: Any]],
        upstream: [String: Any],
        bindings: [String: ResponsesToolNamespaces.Binding],
        wire: ProviderToolContract.Wire
    ) throws {
        let replayed: [[String: Any]]
        if wire == .chatCompletions {
            let messages = try #require(upstream["messages"] as? [[String: Any]])
            replayed = messages.flatMap { $0["tool_calls"] as? [[String: Any]] ?? [] }.map { call in
                ["call_id": call["id"] as Any, "name": (call["function"] as? [String: Any])?["name"] as Any]
            }
        } else {
            replayed = try #require(upstream["input"] as? [[String: Any]]).filter {
                $0["type"] as? String == "function_call"
            }
        }
        let originals = history.filter { $0["type"] as? String == "function_call" }
        #expect(replayed.count == originals.count)
        for (original, replay) in zip(originals, replayed) {
            #expect(original["call_id"] as? String == replay["call_id"] as? String)
            let name = try #require(replay["name"] as? String)
            if let namespace = original["namespace"] as? String {
                #expect(
                    bindings[name]
                        == ResponsesToolNamespaces.Binding(
                            namespace: namespace, name: try #require(original["name"] as? String)
                        ))
            } else {
                #expect(name == original["name"] as? String)
                #expect(bindings[name] == nil)
            }
        }
    }
}
