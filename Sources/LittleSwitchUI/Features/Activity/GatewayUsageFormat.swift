import Foundation

/// Number and label formatting for the menu's gateway stats.
enum GatewayUsageFormat {
    /// Shown wherever a day has not produced a value yet.
    static let placeholder = "—"

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// Token counts run to billions, which do not fit a 320-point menu.
    static func compactCount(_ value: Int) -> String {
        let units: [(divisor: Int, suffix: String)] = [
            (1_000, "K"),
            (1_000_000, "M"),
            (1_000_000_000, "B"),
        ]
        // The unit whose scaled count stays under a full thousand at display
        // rounding keeps the value. A unit takes the count once it reaches
        // 0.9995 of it — a promotion hands up exactly that much from below —
        // and hands it up in turn from 999.5, which rounds to 1000: 999 499
        // reads "999K" while 999 500 reads "1M". The largest unit keeps
        // whatever it rounds to.
        var chosen: (divisor: Int, suffix: String)?
        for unit in units {
            let scaled = Double(value) / Double(unit.divisor)
            guard scaled >= 0.9995 else {
                break
            }
            chosen = unit
            if scaled < 999.5 {
                break
            }
        }
        guard let chosen else {
            return "\(value)"
        }
        let scaled = Double(value) / Double(chosen.divisor)
        return scaled >= 10
            ? "\(Int(scaled.rounded()))\(chosen.suffix)"
            : trimmed(String(format: "%.1f", scaled)) + chosen.suffix
    }

    /// The graph's larger headline can show the precision that the small
    /// metric cells omit: 1,416,000 tokens reads 1.42M instead of 1.4M.
    static func tokenTotal(_ value: Int) -> String {
        let units: [(divisor: Int, suffix: String)] = [
            (1_000, "K"),
            (1_000_000, "M"),
            (1_000_000_000, "B"),
        ]
        let amount = Double(value)
        let chosen = units.last { amount >= Double($0.divisor) * 0.999995 }
        guard let chosen else { return "\(value)" }
        let formatted = (amount / Double(chosen.divisor)).formatted(
            .number.locale(Locale(identifier: "en_US"))
                .grouping(.never)
                .precision(.fractionLength(0...2))
        )
        return formatted + chosen.suffix
    }

    static func errorRate(failures: Double, requests: Double) -> String {
        guard failures > 0, requests > 0 else { return "0%" }
        return percent(failures / requests * 100)
    }

    private static func percent(_ value: Double) -> String {
        value >= 10
            ? "\(Int(value.rounded()))%"
            : "\(trimmed(String(format: "%.1f", value)))%"
    }

    private static func trimmed(_ text: String) -> String {
        text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
