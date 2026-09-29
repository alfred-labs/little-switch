import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native Responses transport accounting", .timeLimit(.minutes(1)))
struct ResponsesNativeMonitoringTests {
    @Test("HTTP and WebSocket native bodies account for usage exactly once", arguments: [false, true])
    func transportParity(webSocket: Bool) async throws {
        let created =
            #"{"type":"response.created","response":{"id":"native_usage","output":[],"usage":{"input_tokens":7}}}"#
        let completed =
            #"{"type":"response.completed","response":{"id":"native_usage","output":[],"usage":{"input_tokens":7,"output_tokens":3}}}"#
        let fixture = try GatewayTests().makeFixture()
        let http = RecordingGatewayTransport(responses: [
            streamingResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                chunks: ["data: \(created)\n\n", "data: \(completed)\n\n"])
        ])
        let store = MonitoringStore()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: http,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            monitoring: GatewayMonitoring(store: store))
        let websocket = SyntheticResponsesWebSocketTransport(automaticReplies: false)
        let upstream = ResponsesUpstreamSession(transport: websocket, limits: .init()) { _ in }
        let owner = Task { await upstream.run() }
        defer { owner.cancel() }
        let executor = ResponsesWebSocketExecutor(
            responder: responder,
            request: webSocketHTTPRequest(),
            limits: .init(),
            upstream: webSocket ? upstream : nil)
        let turn = ResponsesWebSocketTurn(
            id: UUID(),
            streamID: nil,
            body: Data(#"{"model":"gpt-6-astra","input":"Synthetic usage","stream":true}"#.utf8),
            generate: true,
            previousResponseID: nil,
            replacesHistory: false)
        let events = WebSocketEventRecorder()
        let exchange = Task { try await executor.execute(turn) { await events.append($0) } }
        defer { exchange.cancel() }
        if webSocket {
            try await websocket.waitForRequests(1)
            try await websocket.publish(created)
            try await websocket.publish(completed)
        }
        let result = try await valueWithinTimeout(exchange, description: "native usage exchange")
        await upstream.finish()
        await owner.value

        #expect(try JSONValue.parse(result.terminal) == JSONValue.parse(completed))
        let expectedCreated = try #require(JSONValue.parse(created).object)
        #expect(try await events.values() == [expectedCreated])
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        #expect(entries.first?.attributes.usage == .init(inputTokens: 7, outputTokens: 3))
        #expect(await http.requests.count == (webSocket ? 0 : 1))
        #expect(await websocket.requests.count == (webSocket ? 1 : 0))
        #expect(await websocket.activeConnections == 0)
    }
}
