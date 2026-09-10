import Testing

@testable import LittleSwitchUI

@Suite("Gateway usage formatting")
struct GatewayUsageFormatTests {
    @Test("Small metric counts retain their compact format and promote rounded units")
    func compactCounts() {
        #expect(GatewayUsageFormat.compactCount(940) == "940")
        #expect(GatewayUsageFormat.compactCount(8_400) == "8.4K")
        #expect(GatewayUsageFormat.compactCount(1_000_000) == "1M")
        #expect(GatewayUsageFormat.compactCount(6_250_000) == "6.2M")
        #expect(GatewayUsageFormat.compactCount(1_049_000_000) == "1B")
        #expect(GatewayUsageFormat.compactCount(1_500_000_000) == "1.5B")
        #expect(GatewayUsageFormat.compactCount(10_000_000_000) == "10B")
        #expect(GatewayUsageFormat.compactCount(9_999) == "10K")
        #expect(GatewayUsageFormat.compactCount(999_499) == "999K")
        #expect(GatewayUsageFormat.compactCount(999_500) == "1M")
        #expect(GatewayUsageFormat.compactCount(999_999_999) == "1B")
        #expect(GatewayUsageFormat.count(0) == "0")
    }

    @Test("The token headline keeps two useful decimal places and trims redundant zeroes")
    func tokenHeadlines() {
        #expect(GatewayUsageFormat.tokenTotal(0) == "0")
        #expect(GatewayUsageFormat.tokenTotal(940) == "940")
        #expect(GatewayUsageFormat.tokenTotal(1_000) == "1K")
        #expect(GatewayUsageFormat.tokenTotal(1_416) == "1.42K")
        #expect(GatewayUsageFormat.tokenTotal(206_000) == "206K")
        #expect(GatewayUsageFormat.tokenTotal(999_994) == "999.99K")
        #expect(GatewayUsageFormat.tokenTotal(999_995) == "1M")
        #expect(GatewayUsageFormat.tokenTotal(1_416_000) == "1.42M")
        #expect(GatewayUsageFormat.tokenTotal(6_250_000) == "6.25M")
        #expect(GatewayUsageFormat.tokenTotal(1_049_000_000) == "1.05B")
        #expect(GatewayUsageFormat.tokenTotal(Int.max) == "9223372036.85B")
    }

    @Test("Errors show only a percentage including quiet periods")
    func errorPercentages() {
        #expect(GatewayUsageFormat.errorRate(failures: 0, requests: 12) == "0%")
        #expect(GatewayUsageFormat.errorRate(failures: 3, requests: 0) == "0%")
        #expect(GatewayUsageFormat.errorRate(failures: 3, requests: 418) == "0.7%")
        #expect(GatewayUsageFormat.errorRate(failures: 20, requests: 139) == "14%")
        #expect(GatewayUsageFormat.errorRate(failures: 1, requests: 10) == "10%")
        #expect(GatewayUsageFormat.errorRate(failures: 10, requests: 10) == "100%")
    }
}
