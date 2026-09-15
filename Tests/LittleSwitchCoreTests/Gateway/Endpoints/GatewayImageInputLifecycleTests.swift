import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway image input lifecycle")
struct GatewayImageInputLifecycleTests {
    @Test("A persisted observation protects projection and compaction across a seven-day cache boundary")
    func oneWeek() async throws {
        var provider = imageProbeProvider()
        let clock = ResolverTestClock(milliseconds: 1_000_000)
        let prober = RegistryTestProber(outcome: .unsupported)
        await prober.release.open()
        let first = ModelImageInputRegistry(prober: prober, admission: RegistryTestAdmission()) {
            Date(timeIntervalSince1970: Double(clock.now()) / 1_000)
        }
        try await first.configure(provider: provider, generation: UUID())
        _ = try await first.probeIfNeeded(provider: provider, model: provider.models[0], wire: .responses, secret: nil)
        provider.imageInputObservations = await first.observations()
        let saved = try JSONEncoder().encode(provider)
        provider = try JSONDecoder().decode(Provider.self, from: saved)
        let original = [GatewayImageFixture.imageMessage]
        let body = try ResponsesCompactionFixture.data(["model": "model", "input": original])
        let accepted = try ModelImageInputPolicyResolver.acceptsImages(
            provider: provider,
            model: provider.models[0],
            wire: .responses,
            observations: provider.imageInputObservations)
        #expect(!accepted)
        #expect(try ResponsesImageInputProjection.project(body: body, acceptsImages: accepted).omittedImageCount == 1)
        let checkpoint = try ResponsesCompactionFixture.plan(items: original)
            .preservingUninspectedImages()
            .complete(responseBody: ResponsesCompactionFixture.response())
        #expect(
            try ResponsesCompactionFixture.data(ResponsesCompactionFixture.payload(checkpoint)["retained"] as Any)
                == ResponsesCompactionFixture.data(original))
        #expect(
            try CodexCatalog.make(providers: [provider], configuration: .disconnected)
                .models.allSatisfy { $0.inputModalities == ["text"] })
        #expect(
            try await first.probeIfNeeded(
                provider: provider, model: provider.models[0], wire: .responses, secret: nil) == nil)
        #expect(await prober.calls.count == 1)
        await first.shutdown()
        let restarted = ModelImageInputRegistry(prober: prober, admission: RegistryTestAdmission()) {
            Date(timeIntervalSince1970: Double(clock.now()) / 1_000)
        }
        try await restarted.configure(provider: provider, generation: UUID())
        clock.advance(by: 604_799_000)
        #expect(
            try await restarted.probeIfNeeded(
                provider: provider, model: provider.models[0], wire: .responses, secret: nil) == nil)
        #expect(await prober.calls.count == 1)
        clock.advance(by: 1_000)
        #expect(
            try await restarted.probeIfNeeded(
                provider: provider, model: provider.models[0], wire: .responses, secret: nil)?.outcome == .unsupported)
        #expect(await prober.calls.count == 2)
        #expect(await restarted.observations().first?.observedAt == Date(timeIntervalSince1970: 605_800))
        await restarted.shutdown()
    }

    @Test("A burst of lazy callers cannot allocate an unbounded diagnostic wait queue")
    func boundedWaiters() async throws {
        let provider = imageProbeProvider()
        let registry = ModelImageInputRegistry(prober: RegistryTestProber(), admission: RegistryTestAdmission())
        try await registry.configure(provider: provider, generation: UUID())
        let waiters = (0..<128).map { _ in
            Task {
                try await registry.probeIfNeeded(
                    provider: provider, model: provider.models[0], wire: .responses, secret: nil)
            }
        }
        let _: Bool = try await eventually(description: "bounded diagnostic waiters") {
            await registry.waiterCount == 128 ? true : nil
        }
        let outcome = OverflowProbeOutcome()
        let overflow = Task {
            let result = try await registry.probeIfNeeded(
                provider: provider, model: provider.models[0], wire: .responses, secret: nil)
            await outcome.record(skipped: result == nil)
        }
        let _: Bool = try await eventually(description: "overflow is either queued or skipped") {
            let count = await registry.waiterCount
            let skipped = await outcome.skipped
            return count == 129 || skipped ? true : nil
        }
        #expect(await outcome.skipped)
        #expect(await registry.waiterCount == 128)
        for waiter in waiters { waiter.cancel() }
        overflow.cancel()
        await registry.shutdown()
    }
}

private actor OverflowProbeOutcome {
    private(set) var skipped = false
    func record(skipped: Bool) { self.skipped = skipped }
}
