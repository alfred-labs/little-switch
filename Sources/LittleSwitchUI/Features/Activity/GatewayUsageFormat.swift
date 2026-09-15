import Foundation

/// Number and label formatting for the menu's gateway stats.
enum GatewayUsageFormat {
    /// Shown wherever a day has not produced a value yet.
    static let placeholder = "—"

    static func count(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Token counts run to billions, which do not fit a 320-point menu.
    static func compactCount(_ value: Int, locale: Locale = .current) -> String {
        let units: [(divisor: Int, suffix: String)] = [
            (1_000, L10n.string("K", locale: locale)),
            (1_000_000, L10n.string("M", locale: locale)),
            (1_000_000_000, L10n.string("B", locale: locale)),
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
        guard let chosen else { return count(value, locale: locale) }
        let scaled = Double(value) / Double(chosen.divisor)
        let precision = scaled >= 10 ? 0...0 : 0...1
        let formatted = scaled.formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(precision))
        )
        return formatted + chosen.suffix
    }

    /// The graph's larger headline can show the precision that the small
    /// metric cells omit: 1,416,000 tokens reads 1.42M instead of 1.4M.
    static func tokenTotal(_ value: Int, locale: Locale = .current) -> String {
        let units: [(divisor: Int, suffix: String)] = [
            (1_000, L10n.string("K", locale: locale)),
            (1_000_000, L10n.string("M", locale: locale)),
            (1_000_000_000, L10n.string("B", locale: locale)),
        ]
        let amount = Double(value)
        let chosen = units.last { amount >= Double($0.divisor) * 0.999995 }
        guard let chosen else { return count(value, locale: locale) }
        let formatted = (amount / Double(chosen.divisor)).formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(0...2))
        )
        return formatted + chosen.suffix
    }

    static func errorRate(
        failures: Double,
        requests: Double,
        locale: Locale = .current
    ) -> String {
        let ratio = failures > 0 && requests > 0 ? failures / requests : 0
        let percentage = ratio * 100
        let precision = percentage >= 10 ? 0...0 : 0...1
        return ratio.formatted(
            .percent.locale(locale).precision(.fractionLength(precision))
        )
    }
}
