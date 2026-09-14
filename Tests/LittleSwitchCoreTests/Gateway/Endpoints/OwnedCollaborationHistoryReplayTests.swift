import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Owned collaboration history replay")
struct OwnedCollaborationHistoryReplayTests {
    private func bodyWithHistory(tools: [Any]?, input: [Any]) throws -> Data {
        var body: [String: Any] = [
            "model": "little-switch-route",
            "input": input,
            "stream": true,
        ]
        if let tools {
            body["tools"] = tools
        }
        return try JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private var mailItem: [String: Any] {
        [
            "type": "agent_message",
            "id": "amsg_1",
            "author": "/root",
            "recipient": "/root/prenom_1",
            "content": [
                ["type": "input_text", "text": "Message Type: FINAL_ANSWER\nPayload:\nZelmirin"]
            ],
        ]
    }

    @Test("The bridge engages on owned history even without the search tool")
    func bridgeReplayOnlyEngagement() throws {
        let body = try bodyWithHistory(
            tools: [
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
                ]
            ],
            input: [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Go."]],
                ],
                ["type": "web_search_call", "id": "ws_1", "status": "completed"],
                mailItem,
            ]
        )

        let prepared = try #require(
            try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "provider-model",
                configuration: WebSearchConfiguration()
            )
        )

        let upstream = try #require(
            try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any]
        )
        let items = try #require(upstream["input"] as? [[String: Any]])
        #expect(!items.contains { $0["type"] as? String == "web_search_call" })
        let mailConverted = items.contains { item in
            item["type"] as? String == "message"
                && (item["content"] as? [[String: Any]])?.contains {
                    ($0["text"] as? String)?.contains("Zelmirin") == true
                } == true
        }
        #expect(mailConverted)

        let tools = try #require(upstream["tools"] as? [[String: Any]])
        #expect(!tools.contains { $0["type"] as? String == "function" && (($0["name"] as? String) == "web_search") })
        #expect(prepared.toolBindings["collaboration__wait_agent"] != nil)
        #expect(prepared.streaming)
    }

    @Test("History without owned items stays unengaged")
    func noEngagementWithoutOwnedItems() throws {
        let body = try bodyWithHistory(
            tools: [["type": "function", "name": "shell", "parameters": ["type": "object", "properties": [:]]]],
            input: [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Hello."]],
                ]
            ]
        )

        #expect(
            (try OpenAIResponsesWebSearch.prepare(
                body: body,
                targetModel: "provider-model",
                configuration: WebSearchConfiguration()
            )) == nil
        )
    }

    @Test("Native normalization preserves search context and converts mail")
    func historyNormalization() throws {
        let body = try bodyWithHistory(
            tools: [["type": "web_search"]],
            input: [
                ["type": "web_search_call", "id": "ws_1", "status": "completed"],
                mailItem,
                [
                    "type": "agent_message",
                    "id": "amsg_2",
                    "author": "/root",
                    "recipient": "/root/a",
                    "content": [["type": "input_text", "text": ""]],
                ],
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Keep."]],
                ],
            ]
        )

        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        #expect(normalized.droppedMailCount == 1)
        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        #expect(items.count == 3)
        #expect(!items.contains { $0["type"] as? String == "web_search_call" })
        #expect(
            !items.contains { item in
                item["type"] as? String == "agent_message"
            }
        )
        let tools = try #require(object["tools"] as? [Any])
        #expect((tools.first as? [String: Any])?["type"] as? String == "web_search")
    }

    @Test("History without owned items is byte-identical")
    func historyPassthrough() throws {
        let body = try bodyWithHistory(
            tools: [["type": "web_search"]],
            input: [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "Hello."]],
                ]
            ]
        )
        #expect(try OpenAIResponsesNativeNamespacing.normalize(body).body == body)
    }

    @Test("History normalization rejects non-object bodies")
    func historyNormalizationRejectsGarbage() {
        #expect(throws: OpenAIResponsesWebSearch.Error.self) {
            try OpenAIResponsesNativeNamespacing.normalize(Data("[]".utf8))
        }
    }

    @Test("An invalid provider URL seeds the adapter decision safely")
    func invalidURLSeedsNoAdapter() async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = Provider(
            name: "Broken",
            baseURL: "not-a-provider-url",
            authMode: .none
        )
        let ledger = ResponsesCapabilityLedger()
        let state = GatewayState(
            snapshot: fixture.snapshot,
            routingMutationGuard: GatewayRoutingMutationGuard(),
            responsesCapabilities: ledger
        )
        let responder = GatewayResponder(
            state: state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        #expect(await responder.resolvesChatCompletionsAdapter(provider) == false)

        await ledger.record(providerID: provider.id, supportsNative: true)
        #expect(await responder.resolvesChatCompletionsAdapter(provider) == false)
        await ledger.record(providerID: provider.id, supportsNative: false)
        #expect(await responder.resolvesChatCompletionsAdapter(provider) == true)
        #expect(await state.responsesCapabilityVerdicts()[provider.id] == false)
    }

    @Test("A native 404 flips the provider to the adapter within one request")
    func transparent404LearnsAdapter() async throws {
        let providerID = try #require(UUID(uuidString: "057265e6-9c83-4f9d-92a4-93986f1e30e5"))
        let provider = Provider(
            id: providerID,
            name: "ChatOnly",
            baseURL: "https://example.com/api",
            authMode: .bearer,
            models: [
                DiscoveredModel(id: "native-model", maxTokens: 8_192, detectedContextWindow: nil)
            ]
        )
        let mapping = ModelMapping(providerID: providerID, modelID: "native-model")
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: ["claude-opus-5": mapping],
            codex: CodexConfiguration(defaultModel: mapping)
        )
        let secrets = MemorySecretStore()
        try secrets.write("selected-secret", providerID: providerID)
        let state = GatewayState(snapshot: snapshot)
        let fixture = GatewayFixture(snapshot: snapshot, state: state, secrets: secrets)
        let chatBody = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_1",
            "created": 1,
            "choices": [
                [
                    "finish_reason": "stop",
                    "message": ["role": "assistant", "content": "via adapter"],
                ]
            ],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 1,
                "total_tokens": 2,
            ],
        ])
        let chatText = try #require(String(bytes: chatBody, encoding: .utf8))
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: "no such route"),
            response(status: .ok, body: chatText),
        ])
        let responder = GatewayTests().makeApplication(
            fixture: fixture,
            transport: transport
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body = try JSONSerialization.data(withJSONObject: [
            "model": slug,
            "input": "hello",
        ])

        try await responder.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: try #require(String(bytes: body, encoding: .utf8)))
            )
            #expect(result.status == .ok)
        }

        let urls = await transport.requests.map(\.url)
        #expect(urls.first?.contains("/v1/responses") == true)
        #expect(urls.last?.contains("/v1/chat/completions") == true)
        // The flip is recorded on the shared state, where the UI reads it.
        #expect(await state.responsesCapabilities.verdict(for: providerID) == false)
        #expect(await state.responsesCapabilityVerdicts()[providerID] == false)
    }
}
