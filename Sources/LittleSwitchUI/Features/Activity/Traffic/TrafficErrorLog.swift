import Foundation

/// Owned by TrafficLogStore's actor. Retained independently of body-heavy
/// traffic segments, with the same age policy and a separate one-MiB limit.
struct TrafficErrorLog {
    private struct Entry {
        let record: TrafficErrorRecord
        let line: Data
    }

    private let url: URL
    private let maxAge: TimeInterval
    private let byteLimit: Int
    private var entries: [Entry] = []
    private var loaded = false
    private var dirty = false

    var retainedByteCount: Int { entries.reduce(0) { $0 + $1.line.count } }

    init(directory: URL, maxAge: TimeInterval, byteLimit: Int = 1_024 * 1_024) {
        url = directory.appendingPathComponent("errors.jsonl")
        self.maxAge = maxAge
        self.byteLimit = byteLimit
    }

    mutating func append(_ record: TrafficErrorRecord?) throws {
        guard let record, !entries.contains(where: { $0.record.eventID == record.eventID }) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(record)
        line.append(0x0A)
        entries.append(Entry(record: record, line: line))
        dirty = true
    }

    mutating func persist(now: Date, beforeWrite: (URL, Data) throws -> Void) throws {
        // Bound pending records even when the on-disk index cannot be read.
        prune(now: now)
        try load()
        prune(now: now)
        guard dirty else { return }
        let contents = entries.reduce(into: Data()) { $0.append($1.line) }
        try beforeWrite(url, contents)
        try contents.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
        dirty = false
    }

    private mutating func prune(now: Date) {
        let count = entries.count
        let cutoff = now.addingTimeInterval(-maxAge)
        entries.removeAll { $0.record.timestamp < cutoff }
        var bytes = retainedByteCount
        while bytes > byteLimit, !entries.isEmpty {
            bytes -= entries.removeFirst().line.count
        }
        dirty = dirty || entries.count != count
    }

    private mutating func load() throws {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let contents = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var retained: [Entry] = []
            var seen: Set<UUID> = []
            for rawLine in contents.split(separator: 0x0A) {
                let line = Data(rawLine)
                guard let record = try? decoder.decode(TrafficErrorRecord.self, from: line),
                    seen.insert(record.eventID).inserted
                else {
                    dirty = true
                    continue
                }
                retained.append(Entry(record: record, line: line + Data([0x0A])))
            }
            // Pending writes survive an IO failure; replay must not duplicate them.
            entries = retained + entries.filter { !seen.contains($0.record.eventID) }
        }
        loaded = true
    }
}
