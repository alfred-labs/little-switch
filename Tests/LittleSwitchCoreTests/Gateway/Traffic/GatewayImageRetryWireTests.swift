import Foundation
import HummingbirdTesting
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test(
        "An image retry preserves exact numbers in opaque tool schemas",
        arguments: ["1e400", "1e-400", "9007199254740993"]
    )
    func imageRetryPreservesExactOpaqueNumbers(literal: String) async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .badRequest,
                body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Images unsupported"}}"#),
            response(status: .ok, body: #"{"type":"message","content":[]}"#),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let request = #"""
            {"model":"claude-opus-5","tools":[{"name":"calculate","input_schema":{
              "type":"object","vendor":\#(literal)}}],"messages":[{"role":"user","content":[
              {"type":"image","source":{"type":"base64","media_type":"image/png","data":"synthetic-image"}},
              {"type":"text","text":"keep"}]}]}
            """#
        let expected = #"""
            {"model":"glm-5.2","tools":[{"name":"calculate","input_schema":{
              "type":"object","vendor":\#(literal)}}],"messages":[{"role":"user","content":[
              {"type":"text","text":"[Image omitted: the selected model does not accept image input.]"},
              {"type":"text","text":"keep"}]}]}
            """#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request))
            #expect(result.status == .ok)
            let requests = await transport.requests
            try #require(requests.count == 2)
            #expect(requests[0].url == requests[1].url)
            #expect(requests[0].headers["authorization"] == requests[1].headers["authorization"])
            #expect(try JSONValue.parse(requests[1].body) == JSONValue.parse(expected))
            #expect(await fixture.state.sessionRequestCount == 1)
        }

        let event = try #require(recorder.events.first)
        #expect(event.didRetryImages)
        #expect(event.upstreamExchanges.map(\.responseStatus) == [400, 200])
        #expect(event.lifecycle == .completed)
    }
}
