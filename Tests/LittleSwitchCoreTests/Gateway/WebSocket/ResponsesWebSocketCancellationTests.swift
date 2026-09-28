import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket managed cancellation", .timeLimit(.minutes(1)))
struct ResponsesWebSocketCancellationTests {
    @Test(
        "Cancellation releases managed provider admissions, including under socket backpressure",
        arguments: [false, true])
    func releasesAdmission(blockWrite: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: false)
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let model = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let slowTransport = WebSocketSessionTransport()
        let transport: any UpstreamTransport =
            blockWrite
            ? RecordingGatewayTransport(responses: [
                response(
                    status: .ok,
                    body:
                        #"""
                        {"id":"chat","created":1,"choices":[{"finish_reason":"stop",
                        "message":{"role":"assistant","content":"answer"}}],
                        "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}
                        """#
                )
            ]) : slowTransport
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic)
        let session = ResponsesWebSocketSession(responder: responder, request: webSocketHTTPRequest())
        let (messages, input) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let writeStarted = AsyncTestGate()
        let writeGate = AsyncTestGate()
        let task = Task {
            try await session.run(messages: messages) { _ in
                await writeStarted.open()
                try await writeGate.wait()
            }
        }
        defer {
            input.finish()
            task.cancel()
        }
        input.yield(Data(#"{"type":"response.create","model":"\#(model)","input":"slow"}"#.utf8))
        if blockWrite {
            try await writeStarted.wait(description: "socket backpressure")
        } else {
            _ = try await eventually(description: "managed upstream request") {
                await slowTransport.requests.count == 1 ? true : nil
            }
        }
        #expect(await fixture.state.requestPoolSnapshot().totalRunning == 1)
        task.cancel()
        _ = try? await valueWithinTimeout(task, description: "cancelled managed WebSocket turn")
        #expect(await fixture.state.requestPoolSnapshot().totalRunning == 0)
        #expect(await fixture.state.codexSessionRequestCount == 1)
        #expect(traffic.events.count == 1)
        #expect(traffic.events.first?.lifecycle == .cancelled)
    }
}
