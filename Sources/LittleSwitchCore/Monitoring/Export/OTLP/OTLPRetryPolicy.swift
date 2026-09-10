import Foundation

package enum OTLPRetryPolicy {
    package static func delay(
        attempt: Int, retryAfter: String?, now: Date = Date(), jitter: Double = Double.random(in: 0.5...1.5)
    ) -> TimeInterval {
        if let retryAfter {
            let raw = retryAfter.trimmingCharacters(in: .whitespaces)
            let numeric = !raw.isEmpty && raw.utf8.allSatisfy { (48...57).contains($0) }
            if numeric, let seconds = Double(raw), seconds.isFinite {
                return seconds
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            if let date = formatter.date(from: raw) {
                return max(0, date.timeIntervalSince(now))
            }
        }
        let multiplier = jitter.isFinite ? min(1.5, max(0.5, jitter)) : 1
        return min(30, pow(2, Double(min(5, max(0, attempt)))) * multiplier)
    }
}
