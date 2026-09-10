import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring retry deadlines")
struct MonitoringExportRetryScheduleTests {
    @Test("A receiver delay stays anchored to both wall and monotonic time")
    func ordinaryDelay() {
        let schedule = MonitoringExportRetrySchedule(
            delay: 600, now: .init(monotonic: .seconds(2), date: Date(timeIntervalSince1970: 1_002)))
        #expect(schedule.deadline == .seconds(602))
        #expect(schedule.date == Date(timeIntervalSince1970: 1_602))
        #expect(!schedule.isDue(at: .seconds(601)))
        #expect(schedule.isDue(at: .seconds(602)))
    }

    @Test("Unrepresentable receiver delays suspend delivery without overflowing Duration")
    func oversizedDelay() {
        let schedule = MonitoringExportRetrySchedule(
            delay: 1e100, now: .init(monotonic: .seconds(5), date: Date()))
        #expect(schedule.deadline == nil)
        #expect(schedule.date == nil)
        #expect(!schedule.isDue(at: .seconds(1_000_000)))
    }

    @Test("Adding a representable delay cannot overflow a near-limit monotonic clock")
    func elapsedClockOverflow() {
        let schedule = MonitoringExportRetrySchedule(
            delay: 100, now: .init(monotonic: .seconds(Int64.max - 5), date: Date()))
        #expect(schedule.deadline == nil)
        #expect(schedule.date == nil)
    }
}
