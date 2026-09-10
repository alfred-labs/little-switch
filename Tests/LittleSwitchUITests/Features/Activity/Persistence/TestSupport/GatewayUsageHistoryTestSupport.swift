import Foundation

/// Fresh per-test SQLite location so damaged or nuked files never leak
/// between tests.
func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("little-switch-usage-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("usage-history.sqlite", isDirectory: false)
}

/// UTC-fixed calendar so day keys are independent of the host time zone.
var storeCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}
