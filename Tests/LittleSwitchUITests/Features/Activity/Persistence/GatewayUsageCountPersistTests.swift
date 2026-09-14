import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

/// Tool- and web-search call counters must survive a relaunch like every
/// other day statistic, so both get the same persist-and-restore round trip.
@Suite("Gateway usage counter persistence")
struct GatewayUsageCountPersistTests {
    @Test("ToolSearch calls fold into days and survive persistence")
    func toolSearchCountPersists() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )

        await store.start()
        store.record(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                toolSearchCount: 2
            )
        )
        store.record(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                toolSearchCount: 3
            )
        )
        await store.stop()

        let summary = await store.summary(now: now)
        #expect(summary.today.toolSearchCount == 5)

        let restored = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let restoredSummary = await restored.summary(now: now)
        #expect(restoredSummary.today.toolSearchCount == 5)
        await restored.stop()
    }

    @Test("Web search calls fold into days and survive persistence")
    func webSearchCountPersists() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let store = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )

        await store.start()
        store.record(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                webSearchCount: 2
            )
        )
        store.record(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                webSearchCount: 3
            )
        )
        await store.stop()

        let summary = await store.summary(now: now)
        #expect(summary.today.webSearchCount == 5)

        let restored = GatewayUsageHistoryStore(
            configuration: .init(fileURL: fileURL),
            calendar: storeCalendar
        )
        let restoredSummary = await restored.summary(now: now)
        #expect(restoredSummary.today.webSearchCount == 5)
        await restored.stop()
    }
}
