import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image probe real request admission")
struct ModelImageProbeAdmissionTests {
    @Test("A diagnostic shares the real provider limit without a client route or conversation counters")
    func sharedPool() async throws {
        let provider = imageProbeProvider()
        let route = try #require(ClaudeRoute.all.first).id
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: [provider],
                mappings: [route: ModelMapping(providerID: provider.id, modelID: "model")]))
        let admission = ModelImageProbeAdmission()
        await admission.bind(state)
        let first = UUID()
        try await state.admit(
            GatewayRequestAdmission(
                eventID: first,
                capture: await state.routingCapture(),
                client: .claude,
                modelIdentifier: route,
                providerID: provider.id,
                targetModelID: "model",
                retainedBodyBytes: 1))
        #expect(await state.requestPoolSnapshot().totalRunning == 1)
        #expect(await state.sessionRequestCount == 1)
        let second = UUID()
        let waiting = Task { try await admission.admit(eventID: second, provider: provider, modelID: "model") }
        let _: Bool = try await eventually(description: "probe queued in the real provider pool") {
            await state.requestPoolSnapshot().totalWaiting == 1 ? true : nil
        }
        await state.finish(eventID: first)
        try await waiting.value
        #expect(await state.sessionRequestCount == 1)
        #expect(await state.requestPoolSnapshot().totalRunning == 1)
        await admission.finish(eventID: second)
        #expect(await state.requestPoolSnapshot().totalRunning == 0)
        await state.stopAdmissions()
    }

    @Test("Catalog removal invalidates a queued diagnostic and cancellation releases its reservation")
    func queuedInvalidation() async throws {
        let provider = imageProbeProvider()
        let state = GatewayState(snapshot: RoutingSnapshot(generation: 0, providers: [provider], mappings: [:]))
        let admission = ModelImageProbeAdmission()
        await admission.bind(state)
        let active = UUID()
        try await admission.admit(eventID: active, provider: provider, modelID: "model")
        let waiting = Task { try await admission.admit(eventID: UUID(), provider: provider, modelID: "model") }
        let _: Bool = try await eventually(description: "queued diagnostic before catalog removal") {
            await state.requestPoolSnapshot().totalWaiting == 1 ? true : nil
        }
        var empty = provider
        empty.models = []
        await state.replace(providers: [empty], mappings: [:])
        await #expect(throws: GatewayAdmissionError.invalidated) { try await waiting.value }
        await admission.finish(eventID: active)
        #expect(await state.requestPoolSnapshot().totalRunning == 0)
        #expect(await state.requestPoolSnapshot().totalWaiting == 0)
        await state.stopAdmissions()
    }

    @Test("Missing gateway, removed models and reconfigured providers cannot admit a probe")
    func invalidAdmission() async throws {
        let provider = imageProbeProvider()
        let admission = ModelImageProbeAdmission()
        await #expect(throws: GatewayAdmissionError.notAcceptingRequests) {
            try await admission.admit(eventID: UUID(), provider: provider, modelID: "model")
        }
        let state = GatewayState(snapshot: RoutingSnapshot(generation: 0, providers: [provider], mappings: [:]))
        await admission.bind(state)
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await admission.admit(eventID: UUID(), provider: provider, modelID: "missing")
        }
        var changed = provider
        changed.baseURL = "https://new.example"
        await state.replace(providers: [changed], mappings: [:])
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await admission.admit(eventID: UUID(), provider: provider, modelID: "model")
        }
        await state.stopAdmissions()
    }
}
