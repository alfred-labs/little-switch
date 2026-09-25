import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayConversationTests {
    @Test func providerTrafficUsesTheExistingRecordingAndMonitoringPipeline() async throws {
        let recorder = TrafficTestRecorder()
        let store = MonitoringStore()
        let transport = RecordingGatewayTransport(responses: [try chatGPTProviderReply("Recorded")])
        let application = try managedChatGPTApplication(
            transport: transport,
            trafficRecorder: recorder,
            monitoring: GatewayMonitoring(store: store)
        )
        try await application.test(.router) { client in
            _ = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Record this synthetic turn"))
            )
        }
        #expect(recorder.events.count == 1)
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        #expect(entries.first?.attributes.outcome == .success)
        #expect(!String(describing: recorder.events).contains("synthetic-session"))
        #expect(!String(describing: recorder.events).contains("synthetic-cookie"))
    }

    @Test(arguments: [false, true])
    func twoTurnsReopenWithTrustedHistoryAndSeparateCredentials(explicitInitialParent: Bool) async throws {
        let transport = RecordingGatewayTransport(responses: [
            try chatGPTProviderReply("Bonjour"), try chatGPTProviderReply("Deux"),
        ])
        let application = try managedChatGPTApplication(transport: transport)
        try await application.test(.router) { client in
            let first = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(
                    bytes: chatGPTTurnBody(text: "Un", parent: explicitInitialParent ? UUID().uuidString : nil))
            )
            #expect(first.status == .ok)
            let events = try chatGPTNativeEvents(Data(first.body.readableBytesView))
            let final = try #require(
                events.last { ($0["message"] as? [String: Any])?["status"] as? String == "finished_successfully" }
            )
            let id = try #require(final["conversation_id"] as? String)
            let message = try #require(final["message"] as? [String: Any])
            let parent = try #require(message["id"] as? String)
            #expect(ChatGPTConversationID.isOwned(id))
            let second = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Ensuite", conversation: id, parent: parent))
            )
            #expect(String(buffer: second.body).contains("Deux"))
            let reopened = try await client.execute(
                uri: "/backend-api/conversation/" + id,
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            let tree = try chatJSONObject(Data(reopened.body.readableBytesView))
            #expect((tree["mapping"] as? [String: Any])?.count == 5)
            let foreign = try await client.execute(
                uri: "/backend-api/conversation/" + id,
                method: .get,
                headers: [.authorization: "Bearer another-synthetic-account"]
            )
            #expect(foreign.status == .notFound)
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.url == "https://provider.invalid/v1/responses")
            #expect(request.headers["cookie"].isEmpty)
            #expect(request.headers["chatgpt-account-id"].isEmpty)
            #expect(!request.headers["authorization"].contains("Bearer synthetic-session"))
        }
        let secondBody = try chatJSONObject(try #require(requests.last?.body))
        let input = try #require(secondBody["input"] as? [[String: Any]])
        #expect(input.compactMap { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect(
            input.compactMap { ($0["content"] as? [[String: Any]])?.first?["text"] as? String } == [
                "Un", "Bonjour", "Ensuite",
            ]
        )
    }

    @Test func localPrepareAndMixedHistoryNeverReachNativeBackend() async throws {
        let transport = RecordingGatewayTransport(responses: [])
        try await managedChatGPTApplication(transport: transport).test(.router) { client in
            for path in ["/conversation/init", "/f/conversation/prepare"] {
                let response = try await client.execute(
                    uri: "/backend-api" + path,
                    method: .post,
                    headers: chatGPTOwnerHeaders,
                    body: ByteBuffer(
                        string: #"{"model":"example:chat-model","requested_default_model":"example:chat-model"}"#
                    )
                )
                #expect(response.status == .ok)
            }
            let mixed = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Private", conversation: UUID().uuidString))
            )
            #expect(mixed.status == .badRequest)
            let missing = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Private", model: "gone:removed"))
            )
            #expect(missing.status == .notFound)
            let unknown = try await client.execute(
                uri: "/backend-api/conversation/" + ChatGPTConversationID.make() + "/unsupported",
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            #expect(unknown.status == .notFound)
            let query = try await client.execute(
                uri: "/backend-api/unsupported?conversation_id=" + ChatGPTConversationID.make(),
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            #expect(query.status == .notFound)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func providerFailureIsSanitizedAndPersistedWithoutSuccess() async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .internalServerError,
                body: .bytes(ByteBuffer(string: "private-provider-detail"))
            )
        ])
        try await managedChatGPTApplication(transport: transport).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/f/conversation",
                method: .post,
                headers: chatGPTOwnerHeaders,
                body: ByteBuffer(bytes: chatGPTTurnBody(text: "Un"))
            )
            let text = String(buffer: response.body)
            #expect(!text.contains("private-provider-detail"))
            #expect(!text.contains("finished_successfully"))
            let events = try chatGPTNativeEvents(Data(response.body.readableBytesView))
            let id = try #require(events.first?["conversation_id"] as? String)
            let reopened = try await client.execute(
                uri: "/backend-api/conversation/" + id,
                method: .get,
                headers: chatGPTOwnerHeaders
            )
            #expect(String(buffer: reopened.body).contains("\"failed\""))
        }
    }
}

let chatGPTOwnerHeaders: HTTPFields = [.authorization: "Bearer synthetic-session", .cookie: "synthetic-cookie=1"]

func managedChatGPTApplication(
    transport: any UpstreamTransport,
    history: ChatGPTHistoryStore? = nil,
    trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
    monitoring: GatewayMonitoring? = nil
) throws -> Application<ChatGPTGatewayResponder> {
    var provider = chatGPTGatewayFixture().snapshot.providers[0]
    provider.responsesWireOverride = .native
    let state = GatewayState(
        snapshot: RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: [:],
            chatgpt: ChatGPTConfiguration(model: ModelMapping(providerID: provider.id, modelID: "chat-model"))))
    return Application(
        responder: ChatGPTGatewayResponder(
            state: state,
            transport: transport,
            secretStore: MemorySecretStore(),
            requiredAuthorityPort: nil,
            history: try history ?? ChatGPTHistoryStore(),
            trafficRecorder: trafficRecorder,
            monitoring: monitoring
        )
    )
}

func chatGPTTurnBody(
    text: String,
    conversation: String? = nil,
    parent: String? = UUID().uuidString,
    model: String = "example:chat-model"
) throws -> Data {
    var object: [String: Any] = [
        "action": "next", "model": model,
        "messages": [
            [
                "id": UUID().uuidString, "author": ["role": "user"],
                "content": ["content_type": "text", "parts": [text]],
            ]
        ],
    ]
    if let parent { object["parent_message_id"] = parent }
    if let conversation { object["conversation_id"] = conversation }
    return try JSONSerialization.data(withJSONObject: object)
}

func chatGPTProviderReply(_ text: String) throws -> HTTPClientResponse {
    let data = try JSONSerialization.data(withJSONObject: [
        "type": "response.completed",
        "response": [
            "id": "response-synthetic", "status": "completed",
            "output": [
                ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]
            ],
        ],
    ])
    return HTTPClientResponse(
        status: .ok,
        headers: ["content-type": "text/event-stream"],
        body: .bytes(
            ByteBuffer(string: "data: " + (try #require(String(data: data, encoding: .utf8))) + "\n\ndata: [DONE]\n\n")
        )
    )
}

func chatGPTNativeEvents(_ data: Data) throws -> [[String: Any]] {
    try #require(String(data: data, encoding: .utf8)).components(separatedBy: "\n\n").compactMap { frame in
        guard frame.hasPrefix("data: "), frame != "data: [DONE]" else { return nil }
        return try chatJSONObject(Data(frame.dropFirst(6).utf8))
    }
}
