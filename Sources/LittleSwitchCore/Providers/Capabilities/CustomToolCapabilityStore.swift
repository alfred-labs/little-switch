import CryptoKit
import Foundation
import LittleSwitchCommon

/// Only capability metadata crosses this persistence boundary. Endpoint bytes,
/// including any credentials or query, are replaced with a stable SHA-256 digest.
enum CustomToolCapabilityStore {
    struct Key: Codable, Hashable, Sendable {
        let providerID: UUID
        let modelID: String
        let endpointDigest: String
        let wire: String

        init(_ key: CustomToolCapabilityKey) {
            providerID = key.providerID
            modelID = key.modelID
            wire = key.wire
            endpointDigest = SHA256.hash(data: Data(key.endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(providerID)
            hasher.combine(modelID)
            hasher.combine(endpointDigest)
            hasher.combine(wire)
        }
    }

    struct Entry: Codable, Sendable {
        let key: Key
        let mode: CustomToolCapabilityMode
        let observedAt: Date

        func isFresh(at now: Date) -> Bool {
            let age = now.timeIntervalSince(observedAt)
            let lifetime: TimeInterval = mode == .inconclusive ? 3_600 : 604_800
            return age.isFinite && age >= 0 && age < lifetime
        }
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    private static let maximumBytes = 1_024 * 1_024

    static func load(url: URL?, now: Date, maximumEntries: Int) -> [Key: Entry] {
        guard maximumEntries > 0, let url, let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let document = try? decoder.decode(Document.self, from: data), document.schemaVersion == 1 else {
            return [:]
        }
        var result: [Key: Entry] = [:]
        for entry in document.entries.sorted(by: { $0.observedAt > $1.observedAt })
        where entry.isFresh(at: now) && isDigest(entry.key.endpointDigest) {
            guard result.count < maximumEntries else { break }
            if result[entry.key] == nil { result[entry.key] = entry }
        }
        return result
    }

    static func save(_ entries: [Key: Entry], url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let document = Document(schemaVersion: 1, entries: entries.values.sorted { $0.observedAt > $1.observedAt })
        guard let data = try? encoder.encode(document), data.count <= maximumBytes else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // A best-effort cache must not turn a successful model exchange into a filesystem error.
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
