import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Portable stream failure protocols")
struct GatewayPortableStreamFailureTests {
    @Test("Transparent tool rejections expose the same UUID as their local diagnostic", arguments: [true, false])
    func rejectionReference(openAI: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic
        )
        let eventID = UUID()
        let response = responder.streamingResponse(
            failingResponse(error: ProviderToolContract.Error.undeclaredTool(name: "private_tool", namespace: "tools")),
            eventID: eventID,
            attempt: 0,
            errorStyle: openAI ? .openAI : .anthropic
        )
        let recorder = StreamingStageRecorder()
        try await responder.recordingClientResponse(response, eventID: eventID).body.write(
            ObservingResponseBodyWriter(recorder: recorder)
        )
        let text = await recorder.bodyString
        #expect(text.contains("Error ID: \(eventID.uuidString)"))
        #expect(!text.contains("private_tool"))
        let failure = try #require(traffic.events.first?.failure)
        #expect(failure.toolName == "private_tool")
        #expect(failure.toolNamespace == "tools")
    }

    @Test("Transparent streams publish the appropriate terminal error", arguments: [true, false])
    func terminalFailure(openAI: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let recorder = StreamingStageRecorder()
        let response = responder.streamingResponse(
            failingResponse(error: ProviderToolContract.Error.providerOwnedTool),
            eventID: UUID(),
            attempt: 0,
            errorStyle: openAI ? .openAI : .anthropic
        )
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(ObservingResponseBodyWriter(recorder: recorder))
        }
        let text = await recorder.bodyString
        #expect(text.contains(openAI ? "server_error" : "api_error"))
        #expect(!text.contains("response.completed"))
    }

    @Test("A consumer without a selected wire receives the original contract error")
    func noWireFailure() async throws {
        let fixture = try GatewayTests().makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let response = responder.streamingResponse(
            failingResponse(error: ProviderToolContract.Error.undeclaredTool(name: "unknown")),
            eventID: UUID(),
            attempt: 0
        )
        await #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "unknown")) {
            _ = try await responseBodyData(response.body)
        }
    }
}
