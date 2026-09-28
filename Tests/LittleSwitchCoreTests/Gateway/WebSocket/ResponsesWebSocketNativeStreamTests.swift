import Foundation
import HTTPTypes
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses WebSocket streams")
struct ResponsesWebSocketNativeStreamTests {
    @Test("Native SSE without Content-Type delivers tools and a reusable terminal", arguments: [false, true])
    func nativeStream(declaresType: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let transport = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: declaresType ? ["content-type": "text/event-stream"] : [:],
                chunks: [
                    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"native\",\"output\":[]}}\n\n",
                    #"data: {"type":"response.output_item.done","output_index":0,"#
                        + #""item":{"type":"custom_tool_call","id":"tool","call_id":"call","name":"exec","input":"synthetic"}}"#
                        + "\n\n",
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"native\",\"output\":[]}}\n\n",
                ])
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        let accountHeader = try #require(HTTPField.Name("chatgpt-account-id"))
        let executor = ResponsesWebSocketExecutor(
            responder: responder,
            request: webSocketHTTPRequest(headers: [
                .authorization: "Bearer synthetic-session", accountHeader: "synthetic-account",
            ]),
            limits: .init())
        let turn = ResponsesWebSocketTurn(
            id: UUID(),
            streamID: nil,
            body: Data(#"{"model":"gpt-6-astra","input":"Synthetic probe","stream":true}"#.utf8),
            generate: true,
            previousResponseID: nil,
            replacesHistory: false)
        let events = WebSocketEventRecorder()
        let result = try await executor.execute(turn) { await events.append($0) }
        let expectedOutput = try JSONValue.parse(
            #"[{"type":"custom_tool_call","id":"tool","call_id":"call","name":"exec","input":"synthetic"}]"#)
        #expect(result.responseID == "native")
        #expect(try JSONValue.parse(try #require(result.output)) == expectedOutput)
        #expect(
            try JSONValue.parse(result.terminal)
                == ["type": "response.completed", "response": ["id": "native", "output": expectedOutput]])
        #expect(
            try await events.values().map { $0["type"] }
                == [.string("response.created"), .string("response.output_item.done")])
        #expect(traffic.events.first?.lifecycle == .completed)
    }
}
