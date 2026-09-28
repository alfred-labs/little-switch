import Foundation
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("WebSocket turns reuse the Chat adapter and replay history after a model switch")
    func responsesWebSocketConversationReplaysHistoryAndSwitchesModel() async throws {
        let fixture = try makeWebSocketConversationFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
        let firstSlug = CodexCatalog.slug(
            for: ModelMapping(providerID: provider.id, modelID: "glm-5.2"), in: [provider])
        let secondSlug = CodexCatalog.slug(
            for: ModelMapping(providerID: provider.id, modelID: "glm-5.3"), in: [provider])
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: webSocketChatResponse(id: "chatcmpl_ws_one", text: "ONE")),
            response(status: .ok, body: webSocketChatResponse(id: "chatcmpl_ws_two", text: "TWO")),
        ])
        let app = try makeWebSocketApplication(fixture: fixture, transport: transport)
        try await app.test(.live) { client in
            let port = try #require(client.port)
            let url = try #require(URL(string: "ws://localhost:\(port)/v1/responses"))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let socket = session.webSocketTask(with: url)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(
                .string(
                    #"{"type":"response.create","stream_id":"conversation","model":"\#(firstSlug)","input":"First","instructions":"Old instruction"}"#
                ))
            let first = try await webSocketEventsUntilTerminal(socket)
            #expect(first.first?["type"] == .string("response.created"))
            #expect(
                first.contains { $0["type"] == .string("response.output_text.delta") && $0["delta"] == .string("ONE") })
            #expect(first.allSatisfy { $0["stream_id"] == .string("conversation") })
            let firstResponse = try #require(first.last?["response"]?.object)
            #expect(firstResponse["status"] == .string("completed"))
            let previous = try #require(firstResponse["id"]?.string)

            // Send the continuation immediately after terminal delivery: the
            // server must publish the history before publishing that event.
            try await socket.send(
                .string(
                    #"{"type":"response.create","stream_id":"conversation","model":"\#(secondSlug)","input":"Second","previous_response_id":"\#(previous)"}"#
                ))
            let second = try await webSocketEventsUntilTerminal(socket)
            #expect(second.last?["type"] == .string("response.completed"))
            #expect(
                second.contains { $0["type"] == .string("response.output_text.delta") && $0["delta"] == .string("TWO") }
            )
            let terminal = try #require(second.last?["response"]?.object)
            #expect(terminal["model"] == .string(secondSlug))
            #expect(terminal["status"] == .string("completed"))

            // A second connection may use the same logical stream name, but
            // it must not gain access to the first connection's retained turn.
            let otherSocket = session.webSocketTask(with: url)
            otherSocket.resume()
            defer { otherSocket.cancel(with: .normalClosure, reason: nil) }
            try await otherSocket.send(
                .string(
                    #"{"type":"response.create","stream_id":"conversation","model":"\#(secondSlug)","input":"Private","previous_response_id":"\#(previous)"}"#
                ))
            let isolated = try await webSocketEventsUntilTerminal(otherSocket)
            #expect(isolated.count == 1)
            #expect(isolated.first?["type"] == .string("error"))
            #expect(isolated.first?["error"]?.object?["code"] == .string("previous_response_not_found"))
        }
        let requests = await transport.requests
        #expect(
            requests.map(\.url) == Array(repeating: "https://api.z.ai/api/coding/paas/v4/chat/completions", count: 2))
        let firstRequest = try #require(requests.first)
        let secondRequest = try #require(requests.last)
        let firstBody = try #require(JSONValue.parse(firstRequest.body).object)
        let secondBody = try #require(JSONValue.parse(secondRequest.body).object)
        #expect(firstBody["model"] == .string("glm-5.2"))
        #expect(secondBody["model"] == .string("glm-5.3"))
        #expect(secondBody["stream"] == .boolean(true))
        #expect(secondBody["previous_response_id"] == nil)
        #expect(secondBody["stream_id"] == nil)
        let messages = try #require(secondBody["messages"]?.array)
        #expect(messages.compactMap { $0.object?["role"]?.string } == ["user", "assistant", "user"])
        #expect(messages.compactMap { $0.object?["content"]?.string } == ["First", "ONE", "Second"])
        #expect(await fixture.state.codexSessionRequestCount == 2)
    }

    private func makeWebSocketConversationFixture() throws -> GatewayFixture {
        let base = try makeFixture()
        var provider = try #require(base.snapshot.providers.first)
        provider.models.append(DiscoveredModel(id: "glm-5.3"))
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: [provider],
            mappings: base.snapshot.mappings,
            codex: base.snapshot.codex
        )
        return GatewayFixture(snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: base.secrets)
    }
}

private func webSocketChatResponse(id: String, text: String) -> String {
    #"""
    {"id":"\#(id)","created":42,"choices":[{"finish_reason":"stop",
    "message":{"role":"assistant","content":"\#(text)"}}],
    "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}
    """#
}

private func webSocketEventsUntilTerminal(_ socket: URLSessionWebSocketTask) async throws -> [JSONObject] {
    var events: [JSONObject] = []
    for _ in 0..<64 {
        guard case .string(let text) = try await socket.receive() else {
            throw WebSocketConversationTestError.binaryResponse
        }
        let event = try #require(JSONValue.parse(Data(text.utf8)).object)
        events.append(event)
        if let type = event["type"]?.string, ["response.completed", "response.failed", "error"].contains(type) {
            return events
        }
    }
    throw WebSocketConversationTestError.missingTerminal
}

private enum WebSocketConversationTestError: Error {
    case binaryResponse
    case missingTerminal
}
