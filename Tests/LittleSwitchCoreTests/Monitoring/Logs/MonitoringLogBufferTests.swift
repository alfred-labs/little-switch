import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring bounded local log retention")
struct MonitoringLogBufferTests {
    @Test("Retention loss includes equal timestamps and clock rollback")
    func equalTimestampRetention() throws {
        var buffer = MonitoringLogBuffer(instanceID: UUID(), limits: .init(maximumEntries: 2))
        for seconds in [10.0, 10, 10, 5, 4] {
            let appended = buffer.append(.operation(.test, at: Date(timeIntervalSince1970: seconds)))
            #expect(appended)
        }
        let query = try MonitoringLogQuery(parameters: [.init(name: "since", value: "1970-01-01T00:00:10Z")])
        #expect(try buffer.page(query: query).retentionLost)
        let after = try MonitoringLogQuery(parameters: [.init(name: "since", value: "1970-01-01T00:00:11Z")])
        #expect(try !buffer.page(query: after).retentionLost)
    }

    @Test("Evicted cursor positions require explicit restart while the boundary continues")
    func eviction() throws {
        let epoch = UUID()
        var buffer = MonitoringLogBuffer(instanceID: epoch, limits: .init(maximumEntries: 2))
        let first = MonitoringLogEntry.operation(.test, at: Date(timeIntervalSince1970: 1))
        let appendedFirst = buffer.append(first)
        #expect(appendedFirst)
        let oldCursor = try #require(buffer.page(query: MonitoringLogQuery()).nextCursor)
        for seconds in [2.0, 3, 4] {
            let appended = buffer.append(.operation(.test, at: Date(timeIntervalSince1970: seconds)))
            #expect(appended)
        }
        #expect(try buffer.page(query: .init()).entries.count == 2)
        let expiredQuery = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: oldCursor)])
        #expect(throws: MonitoringLogQueryError.cursorExpired) { try buffer.page(query: expiredQuery) }
        let since = try MonitoringLogQuery(parameters: [.init(name: "since", value: "1970-01-01T00:00:01Z")])
        let retained = try buffer.page(query: since)
        #expect(retained.entries.map(\.timestamp) == [Date(timeIntervalSince1970: 3), Date(timeIntervalSince1970: 4)])
        #expect(retained.retentionLost)
    }

    @Test("The whole response byte limit continues at the first entry that did not fit")
    func pageBytes() throws {
        var buffer = MonitoringLogBuffer(instanceID: UUID(), limits: .init(maximumResponseBytes: 1_024))
        for _ in 0..<10 {
            let appended = buffer.append(.operation(.test, at: Date()))
            #expect(appended)
        }
        var query = MonitoringLogQuery()
        var entries: [MonitoringLogEntry] = []
        for _ in 0..<10 {
            let page = try buffer.page(query: query)
            #expect(try page.encoded().count <= 1_024)
            entries += page.entries
            let nextCursor = try #require(page.nextCursor)
            query = try MonitoringLogQuery(parameters: [.init(name: "cursor", value: nextCursor)])
            if entries.count == 10 { break }
        }
        #expect(entries.count == 10)
        #expect(Set(entries.map(\.eventID)).count == 10)
        #expect(try buffer.page(query: query).entries.isEmpty)
    }

    @Test("Entry and retained byte ceilings are enforced independently")
    func storageBytes() throws {
        let entry = MonitoringLogEntry.operation(.test, at: Date())
        var tooSmall = MonitoringLogBuffer(instanceID: UUID(), limits: .init(maximumEntryBytes: 1))
        let rejected = tooSmall.append(entry)
        #expect(!rejected)
        #expect(try tooSmall.page(query: .init()).entries.isEmpty)
        let size = try MonitoringLogPage.encoder().encode(entry).count
        var byteLimited = MonitoringLogBuffer(instanceID: UUID(), limits: .init(maximumBytes: size))
        let first = byteLimited.append(entry)
        let second = byteLimited.append(entry)
        #expect(first)
        #expect(second)
        #expect(try byteLimited.page(query: .init()).entries == [entry])
        #expect(byteLimited.retainedByteCount == size)
    }
}
