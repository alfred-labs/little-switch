import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool flatten bijection")
struct CustomToolFlattenBijectionTests {
    @Test("Flattening active and retired custom identities is injective and reversible")
    func flattenInjectsAndRestoresIdentities() throws {
        let flattened = ResponsesToolNamespaces.flatten(
            tools: declarations(),
            history: [namespacedCall(namespace: "workspace", name: "patch", id: "call_old")]
        )

        let wireNames = flattened.tools.compactMap { $0["name"] as? String }
        #expect(wireNames.count == 5)
        #expect(Set(wireNames).count == wireNames.count)
        #expect(wireNames.allSatisfy { $0.count <= ResponsesToolNamespaces.maximumNameLength })
        #expect(wireNames.contains("workspace__patch"))
        #expect(flattened.tools.allSatisfy { $0["type"] as? String == "custom" })
        #expect(
            flattened.tools.compactMap { $0["format"] as? NSDictionary }
                == [format as NSDictionary, format as NSDictionary, format as NSDictionary])

        let workspaceAlias = try wireName(
            flattened.bindings,
            namespace: "workspace",
            name: "patch"
        )
        let boundaryOne = try wireName(
            flattened.bindings,
            namespace: "a",
            name: "b__c"
        )
        let boundaryTwo = try wireName(
            flattened.bindings,
            namespace: "a__b",
            name: "c"
        )
        #expect(workspaceAlias != "workspace__patch")
        #expect(boundaryOne != boundaryTwo)
        #expect([boundaryOne, boundaryTwo].contains("a__b__c"))

        let expectedIdentities: [ResponsesToolNamespaces.Binding] = [
            .init(namespace: "workspace", name: "patch"),
            .init(namespace: "a", name: "b__c"),
            .init(namespace: "a__b", name: "c"),
            .init(namespace: String(repeating: "n", count: 40), name: String(repeating: "t", count: 40)),
        ]
        #expect(Set(flattened.declaredBindings.values) == Set(expectedIdentities))
        for binding in expectedIdentities {
            let name = try wireName(flattened.bindings, namespace: binding.namespace, name: binding.name)
            #expect(flattened.bindings[name] == binding)
            #expect(flattened.declaredBindings[name] == binding)
            #expect(
                ResponsesToolNamespaces.replayName(
                    bindings: flattened.bindings,
                    namespace: binding.namespace,
                    name: binding.name
                ) == name
            )
        }
    }

    @Test("Retired custom history restores identity without becoming callable")
    func retiredHistoryGetsReplayOnlyBinding() throws {
        let flattened = ResponsesToolNamespaces.flatten(
            tools: [customTool("workspace__patch")],
            history: [namespacedCall(namespace: "workspace", name: "patch", id: "call_old")]
        )

        let names = flattened.tools.compactMap { $0["name"] as? String }
        #expect(names == ["workspace__patch"])
        #expect(flattened.declaredBindings.isEmpty)
        let replayName = ResponsesToolNamespaces.replayName(
            bindings: flattened.bindings,
            namespace: "workspace",
            name: "patch"
        )
        #expect(replayName != "workspace__patch")
        #expect(
            flattened.bindings[replayName]
                == ResponsesToolNamespaces.Binding(namespace: "workspace", name: "patch")
        )
    }

    @Test("Responses custom identities survive public to provider to public to provider")
    func responsesDoubleCycleIsAFixedPoint() throws {
        let firstPublic = try publicRequest(input: publicInput())
        let firstProvider = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: firstPublic,
                targetModel: "upstream",
                configuration: .firecrawlCloud
            )
        )
        let alias = try workspaceAlias(firstProvider.declaredToolBindings)

        let providerResponse = try nativeProviderResponse(name: alias)
        let publicResponse = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: firstProvider,
            traces: [],
            finalTurn: try OpenAIResponsesWebSearch.parseModelTurn(providerResponse),
            usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
        )
        let restoredCall = try publicCallItem(publicResponse, callID: "call_new")
        #expect(
            publicCall(restoredCall)
                == PublicCall(callID: "call_new", name: "patch", namespace: "workspace", input: rawInput)
        )

        var secondInput = publicInput()
        secondInput.append(restoredCall)
        secondInput.append(customOutput(callID: "call_new"))
        let secondProvider = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: publicRequest(input: secondInput),
                targetModel: "upstream",
                configuration: .firecrawlCloud
            )
        )

        #expect(
            try providerDeclarations(firstProvider.upstreamBody, chat: false)
                == providerDeclarations(secondProvider.upstreamBody, chat: false)
        )
        #expect(
            try providerChoice(firstProvider.upstreamBody) == providerChoice(secondProvider.upstreamBody)
        )
        #expect(
            try providerCalls(firstProvider.upstreamBody, chat: false, callID: "call_old")
                == providerCalls(secondProvider.upstreamBody, chat: false, callID: "call_old")
        )
        #expect(
            try providerCalls(secondProvider.upstreamBody, chat: false, callID: "call_new")
                == [ProviderCall(callID: "call_new", wireName: alias, input: rawInput)]
        )
        #expect(try workspaceAlias(firstProvider.declaredToolBindings) == alias)
    }

    @Test("Chat custom identities survive public to provider to public to provider")
    func chatDoubleCycleIsAFixedPoint() throws {
        let firstPublic = try publicRequest(input: publicInput())
        let firstProvider = try OpenAIResponsesChatCompletions.prepare(
            body: firstPublic,
            targetModel: "upstream"
        )
        let alias = try workspaceAlias(firstProvider.declaredToolBindings)

        let publicResponse = try OpenAIResponsesChatCompletions.project(
            responseBody: chatProviderResponse(name: alias),
            prepared: firstProvider
        )
        let restoredCall = try publicCallItem(publicResponse, callID: "call_new")
        #expect(
            publicCall(restoredCall)
                == PublicCall(callID: "call_new", name: "patch", namespace: "workspace", input: rawInput)
        )

        var secondInput = publicInput()
        secondInput.append(restoredCall)
        secondInput.append(customOutput(callID: "call_new"))
        let secondProvider = try OpenAIResponsesChatCompletions.prepare(
            body: publicRequest(input: secondInput),
            targetModel: "upstream"
        )

        #expect(
            try providerDeclarations(firstProvider.upstreamBody, chat: true)
                == providerDeclarations(secondProvider.upstreamBody, chat: true)
        )
        #expect(
            try providerChoice(firstProvider.upstreamBody) == providerChoice(secondProvider.upstreamBody)
        )
        #expect(
            try providerCalls(firstProvider.upstreamBody, chat: true, callID: "call_old")
                == providerCalls(secondProvider.upstreamBody, chat: true, callID: "call_old")
        )
        #expect(
            try providerCalls(secondProvider.upstreamBody, chat: true, callID: "call_new")
                == [ProviderCall(callID: "call_new", wireName: alias, input: rawInput)]
        )
        #expect(try workspaceAlias(secondProvider.declaredToolBindings) == alias)
    }

    @Test("Allowed-tool selection keeps its bijection across both provider cycles", arguments: [false, true])
    func allowedSelectionDoubleCycleIsAFixedPoint(chat: Bool) throws {
        let makeBody = { (input: [[String: Any]]) throws -> Data in
            try chatJSONData([
                "model": "client",
                "input": input,
                "tools": [
                    customTool("workspace__patch"),
                    namespace("workspace", tools: [customTool("patch", format: format)]),
                ],
                "tool_choice": [
                    "type": "allowed_tools",
                    "mode": "required",
                    "tools": [["type": "custom", "namespace": "workspace", "name": "patch"]],
                ],
            ])
        }
        var input = publicInput()
        let firstPublic = try makeBody(input)
        let firstProviderBody: Data
        let firstBindings: [String: ResponsesToolNamespaces.Binding]
        if chat {
            let prepared = try OpenAIResponsesChatCompletions.prepare(
                body: firstPublic,
                targetModel: "upstream"
            )
            firstProviderBody = prepared.upstreamBody
            firstBindings = prepared.declaredToolBindings
        } else {
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: firstPublic,
                    targetModel: "upstream",
                    configuration: .firecrawlCloud
                )
            )
            firstProviderBody = prepared.upstreamBody
            firstBindings = prepared.declaredToolBindings
        }
        let alias = try workspaceAlias(firstBindings)

        let publicResponse: Data
        if chat {
            publicResponse = try OpenAIResponsesChatCompletions.project(
                responseBody: chatProviderResponse(name: alias),
                prepared: try OpenAIResponsesChatCompletions.prepare(
                    body: firstPublic,
                    targetModel: "upstream"
                )
            )
        } else {
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: firstPublic,
                    targetModel: "upstream",
                    configuration: .firecrawlCloud
                )
            )
            publicResponse = try OpenAIResponsesWebSearch.nonStreamingResponse(
                prepared: prepared,
                traces: [],
                finalTurn: try OpenAIResponsesWebSearch.parseModelTurn(
                    nativeProviderResponse(name: alias)
                ),
                usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
            )
        }
        let restoredCall = try publicCallItem(publicResponse, callID: "call_new")
        #expect(
            publicCall(restoredCall)
                == PublicCall(callID: "call_new", name: "patch", namespace: "workspace", input: rawInput)
        )

        input.append(restoredCall)
        input.append(customOutput(callID: "call_new"))
        let secondProviderBody: Data
        if chat {
            secondProviderBody = try OpenAIResponsesChatCompletions.prepare(
                body: try makeBody(input),
                targetModel: "upstream"
            ).upstreamBody
        } else {
            secondProviderBody = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: try makeBody(input),
                    targetModel: "upstream",
                    configuration: .firecrawlCloud
                )
            ).upstreamBody
        }

        #expect(
            try providerDeclarations(firstProviderBody, chat: chat)
                == providerDeclarations(secondProviderBody, chat: chat)
        )
        #expect(try providerChoice(firstProviderBody) == providerChoice(secondProviderBody))
        #expect(
            try providerCalls(firstProviderBody, chat: chat, callID: "call_old")
                == providerCalls(secondProviderBody, chat: chat, callID: "call_old")
        )
        #expect(
            try providerCalls(secondProviderBody, chat: chat, callID: "call_new")
                == [ProviderCall(callID: "call_new", wireName: alias, input: rawInput)]
        )
    }

}
