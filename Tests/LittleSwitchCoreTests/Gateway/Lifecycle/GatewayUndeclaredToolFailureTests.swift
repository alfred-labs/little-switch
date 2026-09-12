import Foundation
import Hummingbird
import Testing

@testable import LittleSwitchCore

@Suite("Gateway undeclared tool failures")
struct GatewayUndeclaredToolFailureTests {
    private let unknownTool = "mise_run_command_with_private_arguments</arg_value>"
    private let expectedMessage = "The provider called a tool that was not allowed by the request."

    @Test("Search bridge names undeclared tools on both provider protocols", arguments: [true, false])
    func searchBridgeFailure(native: Bool) async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let traffic = TrafficTestRecorder()
        let chunks: [Data]
        if native {
            chunks = try [
                responsesGatewaySSE([createdFrame(id: "resp_unknown_tool", createdAt: 100)]),
                responsesGatewaySSE([
                    responsesFrame(
                        "response.output_item.added",
                        [
                            "output_index": 0,
                            "item": functionCallItem(
                                id: "fc_unknown",
                                callID: "call_unknown",
                                name: unknownTool,
                                arguments: "",
                                status: "in_progress"
                            ),
                        ]
                    )
                ]),
            ]
        } else {
            chunks = try unknownChatToolChunks()
        }
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                liveResponsesStreamingResponse(DemandTrackedBodySequence(chunks: chunks))
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic
        )
        let context = try liveResponsesSearchContext(fixture: fixture, native: native)
        let response = try await responder.responsesWebSearchResponse(context: context)
        try await expectNamedFailure(
            responder.recordingClientResponse(response, eventID: context.eventID),
            eventID: context.eventID,
            traffic: traffic
        )
    }

    @Test("Direct Chat Completions adapter names undeclared tools")
    func chatAdapterFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                gatewayChatStreamingResponse(DemandTrackedBodySequence(chunks: try unknownChatToolChunks()))
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic
        )
        let context = try gatewayLiveChatContext(fixture: fixture)
        let response = try await responder.chatCompletionsResponsesResponse(context)
        try await expectNamedFailure(
            responder.recordingClientResponse(response, eventID: context.eventID),
            eventID: context.eventID,
            traffic: traffic
        )
    }

    private func unknownChatToolChunks() throws -> [Data] {
        try chatSSEChunks([
            chatChunkFrame(choices: [chatChoice(delta: ["role": "assistant", "content": ""])]),
            chatChunkFrame(choices: [
                chatChoice(delta: [
                    "tool_calls": [
                        chatToolDelta(index: 0, id: "call_unknown", name: unknownTool, arguments: "")
                    ]
                ])
            ]),
        ])
    }

    private func expectNamedFailure(
        _ response: Response, eventID: UUID, traffic: TrafficTestRecorder
    ) async throws {
        let expectedMessage = "\(self.expectedMessage) Error ID: \(eventID.uuidString)"
        let recorder = StreamingStageRecorder()
        try await response.body.write(ObservingResponseBodyWriter(recorder: recorder))
        let event = try #require(traffic.events.first { $0.id == eventID })
        #expect(event.lifecycle == .failed)
        let failure = try #require(event.failure)
        #expect(failure.message == "Response stream reported failure: undeclaredTool")
        let detail = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(failure)) as? [String: Any])
        #expect(detail["toolName"] as? String == unknownTool)
        let body = await recorder.body
        let events = try ResponsesStreamingTestSupport.events(body)
        #expect(events.map(\.name).suffix(2) == ["error", "response.failed"])
        let error = try #require(events.first { $0.name == "error" })
        #expect(error.payload["code"] as? String == "server_error")
        #expect(error.payload["message"] as? String == expectedMessage)
        let failed = try #require(events.last?.payload["response"] as? [String: Any])
        #expect(failed["status"] as? String == "failed")
        #expect(failed["error"] as? [String: String] == ["code": "server_error", "message": expectedMessage])
        #expect(!events.contains { $0.name == "response.completed" })
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(!text.contains(unknownTool))
        #expect(await recorder.finishCount == 1)
    }
}
