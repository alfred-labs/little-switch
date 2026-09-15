import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway image probe admission failures")
struct GatewayImageProbeFailureTests {
    @Test("Diagnostic cancellation propagates, but unavailability records no capability", arguments: [false, true])
    func diagnosticFailure(cancelled: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let target = try #require(fixture.snapshot.resolveCodex(model: "z.ai/glm-5.2"))
        let prober = ImmediateImageTestProber()
        let admission = FailingImageProbeAdmission(cancelled: cancelled)
        let registry = ModelImageInputRegistry(prober: prober, admission: admission)
        let generation = UUID()
        try await registry.configure(provider: target.provider, generation: generation)
        let state = GatewayState(snapshot: fixture.snapshot, imageInputRegistry: registry)
        var responder = GatewayResponder(
            state: state, transport: RecordingGatewayTransport(responses: []), secretStore: fixture.secrets)
        responder.responsesImageGeneration = generation
        let body = try ResponsesCompactionFixture.data([
            "model": "z.ai/glm-5.2", "input": [GatewayImageFixture.imageMessage],
        ])
        if cancelled {
            await #expect(throws: CancellationError.self) {
                try await responder.probeResponsesImageInput(body: body, target: target, credential: nil)
            }
        } else {
            try await responder.probeResponsesImageInput(body: body, target: target, credential: nil)
        }
        #expect(await admission.calls == 1)
        #expect(await prober.calls == 0)
        #expect(await registry.observations(providerID: target.provider.id, generation: generation).isEmpty)
        #expect(await state.sessionRequestCount == 0)
        await registry.shutdown()
    }
}

private actor FailingImageProbeAdmission: ModelImageProbeAdmitting {
    let cancelled: Bool
    private(set) var calls = 0

    init(cancelled: Bool) { self.cancelled = cancelled }

    func admit(eventID: UUID, provider: Provider, modelID: String) async throws {
        calls += 1
        if cancelled { throw CancellationError() }
        throw GatewayAdmissionError.notAcceptingRequests
    }

    func finish(eventID: UUID) { Issue.record("An ungranted diagnostic permit must not be released") }
}
