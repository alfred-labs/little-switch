import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool capability cache")
struct CustomToolCapabilityCacheTests {
    @Test("Conclusive evidence avoids another probe")
    func reuse() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        #expect(try await cache.mode(for: key) { .native } == .native)
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .native)
    }

    @Test("Inconclusive evidence cools down and every identity component isolates the cache")
    func identitiesAndCooldown() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        #expect(try await cache.mode(for: key) { .inconclusive } == .inconclusive)
        #expect(try await cache.mode(for: key) { .native } == .inconclusive)
        let variants = [
            customCapabilityKey(),
            customCapabilityKey(providerID: key.providerID, modelID: "other"),
            customCapabilityKey(providerID: key.providerID, endpoint: key.endpoint + "?revision=2"),
            customCapabilityKey(providerID: key.providerID, wire: "chatCompletions"),
        ]
        for variant in variants { #expect(try await cache.mode(for: variant) { .native } == .native) }
    }

    @Test("Provider invalidation removes only its observations")
    func invalidate() async throws {
        let cache = CustomToolCapabilityCache()
        let first = customCapabilityKey()
        let second = customCapabilityKey()
        _ = try await cache.mode(for: first) { .native }
        _ = try await cache.mode(for: second) { .native }
        await cache.invalidate(providerIDs: [first.providerID])
        #expect(try await cache.mode(for: first) { .functionEnvelope } == .functionEnvelope)
        #expect(try await cache.mode(for: second) { .functionEnvelope } == .native)
    }

    @Test("Entry count is bounded and a disabled cache still returns the probe result")
    func entryBound() async throws {
        let cache = CustomToolCapabilityCache(maximumEntries: 1)
        let first = customCapabilityKey()
        let second = customCapabilityKey()
        _ = try await cache.mode(for: first) { .native }
        _ = try await cache.mode(for: second) { .native }
        #expect(try await cache.mode(for: first) { .functionEnvelope } == .functionEnvelope)
        let disabled = CustomToolCapabilityCache(maximumEntries: 0)
        #expect(try await disabled.mode(for: first) { .native } == .native)
        #expect(try await disabled.mode(for: first) { .functionEnvelope } == .functionEnvelope)
    }

    @Test("Thrown probes do not install observations")
    func failedProbe() async throws {
        let cache = CustomToolCapabilityCache()
        let key = customCapabilityKey()
        await #expect(throws: URLError.self) { try await cache.mode(for: key) { throw URLError(.unknown) } }
        #expect(try await cache.mode(for: key) { .native } == .native)
    }
}

func customCapabilityKey(
    providerID: UUID = UUID(),
    modelID: String = "model",
    endpoint: String = "https://provider.example/v1/responses",
    wire: String = "responses"
) -> CustomToolCapabilityKey {
    CustomToolCapabilityKey(providerID: providerID, modelID: modelID, endpoint: endpoint, wire: wire)
}
