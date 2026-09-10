import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A forced built-in search choice is rewritten onto the private tool")
    func forcedBuiltInToolChoiceIsRewritten() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "PROVIDER-LEAKME/id?forced",
                    content: [
                        [
                            "type": "tool_use",
                            "id": "tool_forced",
                            "name": "web_search",
                            "input": ["query": "Swift 6.3 release"],
                        ]
                    ],
                    stopReason: "tool_use",
                    inputTokens: 5,
                    outputTokens: 2
                )
            ),
            response(
                status: .ok,
                body: #"{"success":true,"data":{"web":[{"title":"Swift.org","#
                    + #""url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
            ),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_final",
                    content: [["type": "text", "text": "Swift is current."]],
                    stopReason: "end_turn",
                    inputTokens: 8,
                    outputTokens: 4
                )
            ),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )

        let requestBody =
            #"{"model":"claude-opus-5","stream":false,"#
            + #""messages":[{"role":"user","content":"latest Swift"}],"#
            + #""tools":[{"type":"web_search_20250305","max_uses":2},"#
            + #"{"name":"weather","input_schema":{"type":"object"}}],"#
            + #""tool_choice":{"type":"web_search_20250305"}}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: requestBody)
            )
            #expect(result.status == .ok)

            let requests = await transport.requests
            try #require(requests.count == 3)
            // The forced choice named the built-in tool the upstream never
            // sees; the bridge must point it at the private replacement
            // instead of letting the provider reject the request.
            let first = try anthropicObject(requests[0].body)
            let choice = first["tool_choice"] as? [String: Any]
            let expected: [String: Any] = ["type": "tool", "name": "web_search"]
            #expect(choice?.count == expected.count)
            #expect(choice?["type"] as? String == "tool")
            #expect(choice?["name"] as? String == "web_search")
        }

        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
    }
}
