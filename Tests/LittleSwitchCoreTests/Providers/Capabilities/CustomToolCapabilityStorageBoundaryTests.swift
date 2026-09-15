import Foundation
import Testing

import struct os.OSAllocatedUnfairLock

@testable import LittleSwitchCore

@Suite("Custom capability retention ordering")
struct CustomToolCapabilityStorageBoundaryTests {
    @Test("Eviction removes the oldest evidence rather than another fresh model")
    func evictionOrder() async throws {
        let clock = CustomCapabilityStorageClock()
        let cache = CustomToolCapabilityCache(now: { clock.now() }, maximumEntries: 2)
        let oldest = customCapabilityKey(modelID: "oldest")
        let middle = customCapabilityKey(modelID: "middle")
        let newest = customCapabilityKey(modelID: "newest")
        #expect(try await cache.mode(for: oldest) { .native } == .native)
        clock.advance()
        #expect(try await cache.mode(for: middle) { .functionEnvelope } == .functionEnvelope)
        clock.advance()
        #expect(try await cache.mode(for: newest) { .native } == .native)

        #expect(try await cache.mode(for: middle) { .inconclusive } == .functionEnvelope)
        #expect(try await cache.mode(for: newest) { .inconclusive } == .native)
        #expect(try await cache.mode(for: oldest) { .inconclusive } == .inconclusive)
    }

    @Test("Reloading a smaller cache retains the newest persisted evidence")
    func persistedRetentionOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capabilities.json")
        let clock = CustomCapabilityStorageClock()
        let writer = CustomToolCapabilityCache(storeURL: url) { clock.now() }
        let oldest = customCapabilityKey(modelID: "oldest")
        let middle = customCapabilityKey(modelID: "middle")
        let newest = customCapabilityKey(modelID: "newest")
        #expect(try await writer.mode(for: oldest) { .native } == .native)
        clock.advance()
        #expect(try await writer.mode(for: middle) { .inconclusive } == .inconclusive)
        clock.advance()
        #expect(try await writer.mode(for: newest) { .functionEnvelope } == .functionEnvelope)

        let data = try Data(contentsOf: url)
        var document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(document["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["observedAt"] as? Double } == [1_700_000_002, 1_700_000_001, 1_700_000_000])
        // Disk order is not trusted: a valid older schema writer may serialize in another order.
        document["entries"] = Array(entries.reversed())
        try JSONSerialization.data(withJSONObject: document).write(to: url)

        let reader = CustomToolCapabilityCache(storeURL: url, now: { clock.now() }, maximumEntries: 2)
        #expect(try await reader.mode(for: newest) { .native } == .functionEnvelope)
        #expect(try await reader.mode(for: middle) { .native } == .inconclusive)
        #expect(try await reader.mode(for: oldest) { .functionEnvelope } == .functionEnvelope)
    }
}

private final class CustomCapabilityStorageClock: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_700_000_000))

    func now() -> Date { value.withLock { $0 } }

    func advance() { value.withLock { $0 = $0.addingTimeInterval(1) } }
}
