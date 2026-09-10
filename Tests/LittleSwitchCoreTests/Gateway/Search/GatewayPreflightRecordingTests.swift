import Foundation
import Hummingbird
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses preflight failure recording")
struct GatewayPreflightRecordingTests {
    @Test("Responses preflight names dropped agent mail in the traffic log")
    func responsesPreflightRecordsDroppedMail() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let base = try liveResponsesSearchContext(fixture: fixture)
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: base.prepared.upstreamBody,
            originalBody: base.prepared.originalBody,
            originalModel: base.prepared.originalModel,
            originalToolsJSON: base.prepared.originalToolsJSON,
            originalInputJSON: base.prepared.originalInputJSON,
            streaming: base.prepared.streaming,
            maximumUses: base.prepared.maximumUses,
            searchOptions: base.prepared.searchOptions,
            droppedMailCount: 2
        )
        let context = GatewayResponsesWebSearchContext(
            prepared: prepared,
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            searchCredential: base.searchCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: true
        )
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        switch responder.responsesWebSearchPreflight(context: context) {
        case .ready:
            break
        case .rejected:
            Issue.record("Expected the dropped-mail request to still pass preflight")
        }

        let event = try #require(
            recorder.events.last { ($0.annotations ?? []).contains { $0.kind == "agent-mail" } }
        )
        // Preflight passed: the drop is recorded as an annotation, not a
        // failure, so it cannot poison the request's outcome.
        #expect(event.lifecycle == .inProgress)
        #expect(event.failure == nil)
        let note = try #require(event.annotations?.first { $0.kind == "agent-mail" })
        #expect(note.message.contains("2"))
    }

    @Test("Responses preflight records the rejected request cause") func responsesPreflightRecordsCause() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let base = try liveResponsesSearchContext(fixture: fixture)
        let invalid = try JSONSerialization.data(
            withJSONObject: [
                "model": base.prepared.originalModel,
                "input": [["type": "unsupported_item"]],
                "stream": true,
            ] as [String: Any]
        )
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: invalid,
            originalBody: base.prepared.originalBody,
            originalModel: base.prepared.originalModel,
            originalToolsJSON: base.prepared.originalToolsJSON,
            originalInputJSON: base.prepared.originalInputJSON,
            streaming: true,
            maximumUses: base.prepared.maximumUses,
            searchOptions: base.prepared.searchOptions
        )
        let context = GatewayResponsesWebSearchContext(
            prepared: prepared,
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            searchCredential: base.searchCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: true
        )
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        guard
            case .rejected(let response) = responder.responsesWebSearchPreflight(
                context: context
            )
        else {
            Issue.record("Expected the unsupported input item to reject preflight")
            return
        }
        #expect(response.status == .badGateway)

        let failure = try #require(
            recorder.events.last { $0.failure?.kind == "preflight" }
        ).failure
        #expect(failure?.message.contains("invalidProviderRequest") == true)
        #expect(failure?.message.contains("invalidRequest") == true)
    }
}
