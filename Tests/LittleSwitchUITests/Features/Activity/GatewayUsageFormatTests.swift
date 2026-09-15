import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("Gateway usage formatting")
struct GatewayUsageFormatTests {
    @Test("Small metric counts retain their compact format and promote rounded units")
    func compactCounts() {
        let english = Locale(identifier: "en_US")
        let french = Locale(identifier: "fr_FR")
        #expect(GatewayUsageFormat.compactCount(940, locale: english) == "940")
        #expect(GatewayUsageFormat.compactCount(8_400, locale: english) == "8.4K")
        #expect(GatewayUsageFormat.compactCount(8_400, locale: french) == "8,4K")
        #expect(GatewayUsageFormat.compactCount(1_000_000, locale: english) == "1M")
        #expect(GatewayUsageFormat.compactCount(6_250_000, locale: english) == "6.2M")
        #expect(GatewayUsageFormat.compactCount(1_049_000_000, locale: english) == "1B")
        #expect(GatewayUsageFormat.compactCount(1_500_000_000, locale: english) == "1.5B")
        #expect(GatewayUsageFormat.compactCount(10_000_000_000, locale: english) == "10B")
        #expect(GatewayUsageFormat.compactCount(9_999, locale: english) == "10K")
        #expect(GatewayUsageFormat.compactCount(999_499, locale: english) == "999K")
        #expect(GatewayUsageFormat.compactCount(999_500, locale: english) == "1M")
        #expect(GatewayUsageFormat.compactCount(999_999_999, locale: english) == "1B")
        #expect(GatewayUsageFormat.count(0, locale: english) == "0")
    }

    @Test("The token headline keeps two useful decimal places and trims redundant zeroes")
    func tokenHeadlines() {
        let english = Locale(identifier: "en_US")
        let french = Locale(identifier: "fr_FR")
        #expect(GatewayUsageFormat.tokenTotal(0, locale: english) == "0")
        #expect(GatewayUsageFormat.tokenTotal(940, locale: english) == "940")
        #expect(GatewayUsageFormat.tokenTotal(1_000, locale: english) == "1K")
        #expect(GatewayUsageFormat.tokenTotal(1_416, locale: english) == "1.42K")
        #expect(GatewayUsageFormat.tokenTotal(1_416, locale: french) == "1,42K")
        #expect(GatewayUsageFormat.tokenTotal(206_000, locale: english) == "206K")
        #expect(GatewayUsageFormat.tokenTotal(999_994, locale: english) == "999.99K")
        #expect(GatewayUsageFormat.tokenTotal(999_995, locale: english) == "1M")
        #expect(GatewayUsageFormat.tokenTotal(1_416_000, locale: english) == "1.42M")
        #expect(GatewayUsageFormat.tokenTotal(6_250_000, locale: english) == "6.25M")
        #expect(GatewayUsageFormat.tokenTotal(1_049_000_000, locale: english) == "1.05B")
        #expect(GatewayUsageFormat.tokenTotal(Int.max, locale: english) == "9223372036.85B")
    }

    @Test("Errors show only a percentage including quiet periods")
    func errorPercentages() {
        let english = Locale(identifier: "en_US")
        let french = Locale(identifier: "fr_FR")
        #expect(GatewayUsageFormat.errorRate(failures: 0, requests: 12, locale: english) == "0%")
        #expect(GatewayUsageFormat.errorRate(failures: 3, requests: 0, locale: english) == "0%")
        #expect(GatewayUsageFormat.errorRate(failures: 3, requests: 418, locale: english) == "0.7%")
        #expect(GatewayUsageFormat.errorRate(failures: 20, requests: 139, locale: english) == "14%")
        #expect(GatewayUsageFormat.errorRate(failures: 1, requests: 10, locale: english) == "10%")
        #expect(GatewayUsageFormat.errorRate(failures: 10, requests: 10, locale: english) == "100%")
        #expect(GatewayUsageFormat.errorRate(failures: 3, requests: 418, locale: french) == "0,7 %")
        #expect(GatewayUsageFormat.errorRate(failures: 20, requests: 139, locale: french) == "14 %")
    }
}
