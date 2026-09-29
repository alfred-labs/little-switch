import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Native initial rejection admission", .timeLimit(.minutes(1)))
struct ResponsesUpstreamRejectionTests {
    @Test(
        "Flat errors use an HTTP error object and only valid rejection statuses",
        arguments: [400, 422, 429, 503, 200, 0])
    func flatError(status: Int) throws {
        let event: JSONObject = [
            "type": "error", "status": .integer(status), "code": "synthetic_code", "message": "Synthetic rejection",
            "param": "input",
        ]
        let rejection = try ResponsesUpstreamRejection(event)
        let expectedStatus = (400..<600).contains(status) ? status : 400
        let type =
            expectedStatus >= 500
            ? "server_error" : (expectedStatus == 429 ? "rate_limit_error" : "invalid_request_error")
        #expect(rejection.status.code == expectedStatus)
        #expect(
            try JSONValue.parse(rejection.body) == [
                "error": [
                    "type": .string(type), "code": "synthetic_code", "message": "Synthetic rejection", "param": "input",
                ]
            ])
    }

    @Test("Missing status defaults to 400 and nested error fields are preserved")
    func defaultsAndNested() throws {
        let defaults = try ResponsesUpstreamRejection(["type": "error"])
        #expect(defaults.status.code == 400)
        #expect(
            try JSONValue.parse(defaults.body) == [
                "error": [
                    "type": "invalid_request_error", "code": "upstream_error", "message": "Provider request failed",
                    "param": .null,
                ]
            ])
        let nested: JSONValue = ["message": "Synthetic nested rejection", "details": ["number": 42]]
        let rejection = try ResponsesUpstreamRejection(["type": "error", "status": "invalid", "error": nested])
        #expect(rejection.status.code == 400)
        #expect(try JSONValue.parse(rejection.body) == ["error": nested])
    }

    @Test(
        "Native passthrough renders identical HTTP and initial WebSocket rejections", arguments: [400, 422, 429, 503])
    func errorParity(status: Int) async throws {
        let error: JSONValue = [
            "error": [
                "type": "synthetic_error", "code": "synthetic_code", "message": "Synthetic rejection", "param": "input",
            ]
        ]
        var outcomes: [JSONValue] = []
        for webSocket in [false, true] {
            let fixture = try GatewayTests().makeFixture()
            let http = RecordingGatewayTransport(responses: [
                response(
                    status: .init(statusCode: status),
                    body: try #require(String(data: error.serializedData(), encoding: .utf8))
                )
            ])
            let responder = GatewayResponder(
                state: fixture.state, transport: http, secretStore: fixture.secrets, requiredAuthorityPort: nil)
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
                streamID: "A",
                body: Data(#"{"model":"gpt-6-astra","input":"Synthetic request","stream":true}"#.utf8),
                generate: true,
                previousResponseID: nil,
                replacesHistory: false)
            let events = WebSocketEventRecorder()
            let exchange = Task { try await executor.execute(turn) { await events.append($0) } }
            defer { exchange.cancel() }
            if webSocket {
                try await websocket.waitForRequests(1)
                var envelope = try #require(error.object)
                envelope["type"] = "error"
                envelope["status"] = .integer(status)
                try await websocket.publish(
                    #require(String(data: JSONValue.object(envelope).serializedData(), encoding: .utf8)))
            }
            let result = try await valueWithinTimeout(exchange, description: "native rejection parity")
            outcomes.append(try JSONValue.parse(result.terminal))
            #expect(try await events.values().isEmpty)
            #expect(await http.requests.count == (webSocket ? 0 : 1))
            await upstream.finish()
            try await valueWithinTimeout(owner, description: "native rejection parity cleanup")
        }
        #expect(outcomes.count == 2)
        #expect(outcomes.first == outcomes.last)
        #expect(outcomes.first?.object?["status"] == .integer(status))
        #expect(outcomes.first?.object?["error"] == error.object?["error"])
    }
}
