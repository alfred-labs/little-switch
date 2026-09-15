import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Image input registry")
struct ModelImageInputRegistryTests {
    @Test("Concurrent callers share a probe; cancelling one waiter does not cancel another")
    func coalescing() async throws {
        let provider = imageProbeProvider()
        let prober = RegistryTestProber()
        let registry = ModelImageInputRegistry(prober: prober, admission: RegistryTestAdmission())
        try await registry.configure(provider: provider, generation: UUID())
        let first = probeTask(registry, provider)
        let second = probeTask(registry, provider)
        let _: Bool = try await eventually(description: "two coalesced probe waiters") {
            let waiters = await registry.waiterCount
            let calls = await prober.calls.count
            return waiters == 2 && calls == 1 ? true : nil
        }
        #expect(await prober.calls.count == 1)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await prober.release.open()
        #expect(try await second.value?.outcome == .verified)
        #expect(await registry.observations().count == 1)
        #expect(try await probeTask(registry, provider).value == nil)
        await registry.shutdown()
    }

    @Test("Unknown results cool down for an hour without overwriting a conclusive observation")
    func cooldown() async throws {
        var provider = imageProbeProvider()
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        let observation = ModelImageInputObservation(
            key: key, verdict: .unsupported, source: .providerRejection, observedAt: Date(timeIntervalSince1970: 0))
        provider.imageInputObservations = [observation]
        let clock = ResolverTestClock(milliseconds: 604_800_000)
        let prober = RegistryTestProber(outcome: .inconclusive(.wrongAnswer))
        await prober.release.open()
        let registry = ModelImageInputRegistry(prober: prober, admission: RegistryTestAdmission()) {
            Date(timeIntervalSince1970: Double(clock.now()) / 1_000)
        }
        let diagnostics = ImageProbeDiagnosticRecorder()
        await registry.setHandlers(
            onObservation: { _, _ in },
            onProbeDiagnostic: { diagnostic, _ in
                await diagnostics.record(diagnostic)
            })
        try await registry.configure(provider: provider, generation: UUID())
        #expect(try await probeTask(registry, provider).value?.outcome == .inconclusive(.wrongAnswer))
        clock.advance(by: 3_599_000)
        #expect(try await probeTask(registry, provider).value == nil)
        clock.advance(by: 1_000)
        #expect(try await probeTask(registry, provider).value != nil)
        #expect(await prober.calls.count == 2)
        #expect(await registry.observations() == [observation])
        #expect(await diagnostics.latest.count == 1)
        await registry.shutdown()
    }

    @Test("Two global jobs and one per provider are scheduled without losing queued models")
    func concurrencyBudget() async throws {
        let one = imageProbeProvider(models: ["a", "b"])
        let two = imageProbeProvider()
        let three = imageProbeProvider()
        let prober = RegistryTestProber()
        let admission = RegistryTestAdmission()
        let registry = ModelImageInputRegistry(prober: prober, admission: admission)
        for provider in [one, two, three] { try await registry.configure(provider: provider, generation: UUID()) }
        let tasks = [
            probeTask(registry, one), probeTask(registry, one, model: one.models[1]),
            probeTask(registry, two), probeTask(registry, three),
        ]
        let _: Bool = try await eventually(description: "four probe waiters and two running") {
            let count = await registry.waiterCount
            let calls = await prober.calls.count
            return count == 4 && calls == 2 ? true : nil
        }
        #expect(await admission.maximumActive == 2)
        #expect(Set(await prober.calls.map(\.providerID)).count == 2)
        await prober.release.open()
        for task in tasks { #expect(try await task.value?.outcome == .verified) }
        #expect(await prober.calls.count == 4)
        #expect(await admission.active.isEmpty)
        await registry.shutdown()
    }

    @Test("Invalidation and shutdown cancel jobs and never publish a previous generation")
    func invalidation() async throws {
        let provider = imageProbeProvider()
        let prober = RegistryTestProber()
        let admission = RegistryTestAdmission()
        let registry = ModelImageInputRegistry(prober: prober, admission: admission)
        let diagnostics = ImageProbeDiagnosticRecorder()
        await registry.setHandlers(
            onObservation: { _, _ in },
            onProbeDiagnostic: { diagnostic, _ in
                await diagnostics.record(diagnostic)
            })
        let generation = UUID()
        try await registry.configure(provider: provider, generation: generation)
        let task = probeTask(registry, provider)
        let _: Bool = try await eventually(description: "active probe") { await prober.calls.count == 1 ? true : nil }
        await registry.invalidate(providerID: provider.id)
        await #expect(throws: CancellationError.self) { try await task.value }
        await registry.shutdown()
        #expect(await admission.active.isEmpty)
        #expect(await registry.observations().isEmpty)
        #expect(await diagnostics.latest.isEmpty)
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        await registry.record(
            ModelImageInputObservation(
                key: key, verdict: .verified, source: .visualProbe, observedAt: Date()), generation: generation)
        #expect(await registry.observations().isEmpty)
    }

    @Test("A previous credential epoch cannot probe or deliver a delayed observation")
    func staleGeneration() async throws {
        let provider = imageProbeProvider()
        let registry = ModelImageInputRegistry(prober: RegistryTestProber(), admission: RegistryTestAdmission())
        let old = UUID()
        try await registry.configure(provider: provider, generation: old)
        let new = UUID()
        try await registry.configure(provider: provider, generation: new)
        await #expect(throws: GatewayAdmissionError.invalidated) {
            try await registry.probeIfNeeded(
                provider: provider,
                model: provider.models[0],
                wire: .responses,
                secret: "synthetic-old",
                generation: old)
        }
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: "model", wire: .responses)
        await registry.record(
            ModelImageInputObservation(key: key, verdict: .verified, source: .visualProbe, observedAt: Date()),
            generation: old)
        #expect(await registry.observations().isEmpty)
        #expect(await registry.generation(providerID: provider.id) == new)
        await registry.shutdown()
    }

    private func probeTask(
        _ registry: ModelImageInputRegistry, _ provider: Provider, model: DiscoveredModel? = nil
    ) -> Task<ModelImageInputProbeResult?, any Error> {
        Task {
            try await registry.probeIfNeeded(
                provider: provider, model: model ?? provider.models[0], wire: .responses, secret: nil)
        }
    }
}

actor RegistryTestProber: ModelImageInputProbing {
    struct Call: Sendable {
        let providerID: UUID
        let modelID: String
    }
    let release = AsyncTestGate()
    private(set) var calls: [Call] = []
    let outcome: ModelImageInputProbeOutcome

    init(outcome: ModelImageInputProbeOutcome = .verified) { self.outcome = outcome }

    func probe(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?
    ) async throws -> ModelImageInputProbeResult {
        calls.append(Call(providerID: provider.id, modelID: model.id))
        try await release.wait()
        return ModelImageInputProbeResult(outcome: outcome, usage: nil, startedAt: Date(), durationSeconds: 1)
    }
}

actor RegistryTestAdmission: ModelImageProbeAdmitting {
    private(set) var active: Set<UUID> = []
    private(set) var maximumActive = 0

    func admit(eventID: UUID, provider: Provider, modelID: String) {
        active.insert(eventID)
        maximumActive = max(maximumActive, active.count)
    }

    func finish(eventID: UUID) { active.remove(eventID) }
}
