import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Custom capability metadata persistence")
struct CustomToolCapabilityPersistenceTests {
    @Test("Evidence expires at precisely seven days; inconclusive cooldown at one hour", arguments: expirations)
    func expiry(fixture: CustomCapabilityExpiryCase) async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let observed = Date(timeIntervalSince1970: 1_700_000_000)
        let key = customCapabilityKey()
        let writer = CustomToolCapabilityCache(storeURL: url) { observed }
        _ = try await writer.mode(for: key) { fixture.mode }
        let reader = CustomToolCapabilityCache(storeURL: url) { observed.addingTimeInterval(fixture.age) }
        #expect(try await reader.mode(for: key) { .functionEnvelope } == fixture.expected)
    }

    @Test("The durable record contains metadata and a digest, never endpoint secrets")
    func privacy() async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let key = customCapabilityKey(
            endpoint: "https://synthetic-user:synthetic-password@example.test/v1/responses?token=synthetic-token")
        let cache = CustomToolCapabilityCache(storeURL: url)
        _ = try await cache.mode(for: key) { .native }
        let data = try Data(contentsOf: url)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("synthetic-") && !json.contains("example.test") && !json.contains("https://"))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["schemaVersion"] as? Int == 1)
        let reader = CustomToolCapabilityCache(storeURL: url)
        #expect(try await reader.mode(for: key) { .functionEnvelope } == .native)
        await reader.invalidate(providerIDs: [key.providerID])
        let reloaded = CustomToolCapabilityCache(storeURL: url)
        #expect(try await reloaded.mode(for: key) { .functionEnvelope } == .functionEnvelope)
    }

    @Test("Corrupt, unknown-schema and oversized stores are ignored", arguments: CustomCapabilityCorruptStore.allCases)
    func corrupt(fixture: CustomCapabilityCorruptStore) async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data(fixture.body.utf8).write(to: url)
        let cache = CustomToolCapabilityCache(storeURL: url)
        #expect(try await cache.mode(for: customCapabilityKey()) { .native } == .native)
    }

    @Test("Read and write failures are best effort")
    func storeFailure() async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not a directory".utf8).write(to: url)
        let cache = CustomToolCapabilityCache(storeURL: url.appendingPathComponent("impossible.json"))
        let key = customCapabilityKey()
        #expect(try await cache.mode(for: key) { .native } == .native)
        #expect(try await cache.mode(for: key) { .functionEnvelope } == .native)
    }

    private func temporaryStore() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("capabilities.json")
    }

    private static let expirations: [CustomCapabilityExpiryCase] = [
        .init(mode: .native, age: 604_799, expected: .native),
        .init(mode: .native, age: 604_800, expected: .functionEnvelope),
        .init(mode: .inconclusive, age: 3_599, expected: .inconclusive),
        .init(mode: .inconclusive, age: 3_600, expected: .functionEnvelope),
        .init(mode: .native, age: -1, expected: .functionEnvelope),
    ]
}

struct CustomCapabilityExpiryCase: Sendable {
    let mode: CustomToolCapabilityMode
    let age: TimeInterval
    let expected: CustomToolCapabilityMode
}

enum CustomCapabilityCorruptStore: CaseIterable {
    case invalid, unknownSchema, oversized

    var body: String {
        switch self {
        case .invalid: "not-json"
        case .unknownSchema: #"{"schemaVersion":99,"entries":[]}"#
        case .oversized: String(repeating: "x", count: 1_048_577)
        }
    }
}
