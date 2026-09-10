import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Portable stream failure protocols")
struct GatewayPortableStreamFailureTests {
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
            failingResponse(error: ProviderToolContract.Error.undeclaredTool), eventID: UUID(), attempt: 0
        )
        await #expect(throws: ProviderToolContract.Error.undeclaredTool) {
            _ = try await responseBodyData(response.body)
        }
    }
}
