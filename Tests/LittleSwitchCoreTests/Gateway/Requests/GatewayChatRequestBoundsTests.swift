import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Chat-adapted request bounds")
struct GatewayChatRequestBoundsTests {
    @Test(
        "Canonical Z.AI rejects post-adaptation growth before logging or transport",
        arguments: [false, true]
    )
    func rejectsAdaptedGrowth(streaming: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let context = try minimalZAIContext(
            fixture: fixture,
            streaming: streaming
        )
        let mode: ResponsesChatCompletionsMode =
            streaming ? .streaming(toolStream: true) : .buffered
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: context.body,
            targetModel: context.target.model.id,
            mode: mode
        )
        #expect(context.target.provider.name == "z.ai")
        try #require(prepared.upstreamBody.count > context.body.count)

        let transport = RecordingGatewayTransport(responses: [
            response(status: .badGateway, body: #"{"private":"upstream"}"#)
        ])
        let traffic = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: context.body.count,
            requiredAuthorityPort: nil,
            trafficRecorder: traffic
        )

        let response = try await responder.chatCompletionsResponsesResponse(context)
        let body = try await responseBodyData(response.body)
        let root = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let error = try #require(root["error"] as? [String: Any])

        #expect(response.status == .contentTooLarge)
        #expect(error["message"] as? String == "Request body is too large")
        #expect(await transport.requests.isEmpty)
        #expect(traffic.events.isEmpty)
    }
}

private func minimalZAIContext(
    fixture: GatewayFixture,
    streaming: Bool
) throws -> TransparentResponsesContext {
    let routed = try gatewayLiveChatContext(
        fixture: fixture,
        streaming: streaming,
        includeTools: false
    )
    var root: [String: Any] = [
        "model": routed.model,
        "input": "x",
        "instructions": "i",
    ]
    if streaming {
        root["stream"] = true
    }
    let body = try JSONSerialization.data(
        withJSONObject: root,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return TransparentResponsesContext(
        body: body,
        model: routed.model,
        target: routed.target,
        credential: routed.credential,
        incomingHeaders: routed.incomingHeaders,
        eventID: UUID(),
        streaming: streaming
    )
}
