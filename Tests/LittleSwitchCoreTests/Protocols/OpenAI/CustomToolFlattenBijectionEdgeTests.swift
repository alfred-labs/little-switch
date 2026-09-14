import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

extension CustomToolFlattenBijectionTests {
    @Test("Retired custom history never authorizes a new call", arguments: [false, true])
    func retiredHistoryDoesNotAuthorizeEmission(chat: Bool) throws {
        let publicBody = try chatJSONData([
            "model": "client",
            "input": [
                namespacedCall(namespace: "workspace", name: "patch", id: "call_old"),
                customOutput(callID: "call_old"),
            ],
            "tools": [customTool("workspace__patch")],
        ])
        let providerBody: Data
        let replayAlias: String
        if chat {
            let prepared = try OpenAIResponsesChatCompletions.prepare(
                body: publicBody,
                targetModel: "upstream"
            )
            providerBody = prepared.upstreamBody
            replayAlias = try workspaceAlias(prepared.toolBindings)
        } else {
            let prepared = try #require(
                try OpenAIResponsesWebSearch.prepare(
                    body: publicBody,
                    targetModel: "upstream",
                    configuration: .firecrawlCloud
                )
            )
            providerBody = prepared.upstreamBody
            replayAlias = try workspaceAlias(prepared.toolBindings)
        }

        let contract = try ProviderToolContract(
            wire: chat ? .chatCompletions : .responses,
            requestBody: providerBody
        )
        let response: Data
        if chat {
            response = try chatProviderResponse(name: replayAlias)
        } else {
            response = try nativeProviderResponse(name: replayAlias)
        }
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: replayAlias)) {
            try contract.validateBuffered(response)
        }
    }

    @Test("Duplicate and malformed namespace declarations are rejected", arguments: [false, true])
    func invalidDeclarationsAreRejected(chat: Bool) throws {
        let duplicate: [[String: Any]] = [
            namespace("workspace", tools: [customTool("patch"), customTool("patch")])
        ]
        let malformed: [[String: Any]] = [
            ["type": "namespace", "name": "workspace"]
        ]
        for tools in [duplicate, malformed] {
            let body = try chatJSONData([
                "model": "client",
                "input": "Inspect the files.",
                "tools": tools,
            ])
            if chat {
                #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                    _ = try OpenAIResponsesChatCompletions.prepare(
                        body: body,
                        targetModel: "upstream"
                    )
                }
            } else {
                #expect(throws: ProviderToolContract.Error.invalidRequest) {
                    _ = try OpenAIResponsesWebSearch.prepare(
                        body: body,
                        targetModel: "upstream",
                        configuration: .firecrawlCloud
                    )
                }
            }
        }
    }

    @Test("An unknown native custom name remains flat instead of borrowing a namespace")
    func unknownNativeNameIsNotRestoredAsNamespaced() throws {
        let publicBody = try chatJSONData([
            "model": "client",
            "input": "Inspect the files.",
            "tools": [namespace("workspace", tools: [customTool("patch")])],
        ])
        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: publicBody,
                targetModel: "upstream",
                configuration: .firecrawlCloud
            )
        )
        let response = try OpenAIResponsesWebSearch.nonStreamingResponse(
            prepared: prepared,
            traces: [],
            finalTurn: try OpenAIResponsesWebSearch.parseModelTurn(
                nativeProviderResponse(name: "unknown")
            ),
            usage: ResponsesUsage(inputTokens: 1, outputTokens: 1)
        )
        let call = try publicCallItem(response, callID: "call_new")
        #expect(
            publicCall(call)
                == PublicCall(callID: "call_new", name: "unknown", namespace: nil, input: rawInput)
        )
    }
}
