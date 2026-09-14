import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Transparent Responses history")
struct TransparentResponsesHistoryTests {
    @Test("The transparent path names dropped agent mail in the traffic log")
    func transparentHistoryRecordsDroppedMail() async throws {
        let providerID = try #require(UUID(uuidString: "057265e6-9c83-4f9d-92a4-93986f1e30e5"))
        let provider = Provider(
            id: providerID,
            name: "Native",
            baseURL: "https://example.com/api",
            authMode: .bearer,
            models: [
                DiscoveredModel(id: "native-model", maxTokens: 8_192, detectedContextWindow: nil)
            ],
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
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: "{\"id\":\"resp_1\",\"output\":[],\"usage\":{}}")
        ])
        let recorder = TrafficTestRecorder()
        let responder = GatewayTests().makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body = try JSONSerialization.data(withJSONObject: [
            "model": slug,
            "input": [
                [
                    "type": "agent_message",
                    "id": "amsg_1",
                    "content": "not readable mail",
                ]
            ],
        ])

        try await responder.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: try #require(String(bytes: body, encoding: .utf8)))
            )
            #expect(result.status == .ok)
        }

        let event = try #require(
            recorder.events.last { ($0.annotations ?? []).contains { $0.kind == "agent-mail" } }
        )
        // The drop is an observation on a request that went on to succeed:
        // it must not fail the event, and the real completion stands.
        #expect(event.lifecycle == .completed)
        #expect(event.failure == nil)
        #expect(event.finalStatus == 200)
        let note = try #require(event.annotations?.first { $0.kind == "agent-mail" })
        #expect(note.message.contains("1 unparseable agent message"))
    }
}
