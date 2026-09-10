import Testing

@testable import LittleSwitchCore

@Suite("Gateway Anthropic initial usage mappings")
struct GatewayAnthropicInitialUsageMappingTests {
    @Test("Traffic mappings cover native, provider, and every local fallback outcome")
    func trafficMappings() {
        #expect(anthropicTrafficEstimate(for: .native(7)) == nil)
        #expect(
            anthropicTrafficEstimate(
                for: .providerEstimate(tokens: 8, elapsedMilliseconds: 9)
            )?.providerOutcome == .success
        )

        let outcomes: [(AnthropicProviderCountOutcome, TrafficProviderCountOutcome)] = [
            (.success, .success),
            (.timeout, .timeout),
            (.http, .http),
            (.invalid, .invalid),
            (.transport, .transport),
            (.circuitOpen, .circuitOpen),
        ]
        for (provider, traffic) in outcomes {
            #expect(anthropicTrafficProviderOutcome(provider) == traffic)
            #expect(
                anthropicTrafficEstimate(
                    for: .localEstimate(
                        tokens: 10,
                        providerOutcome: provider,
                        elapsedMilliseconds: 11
                    )
                )?.providerOutcome == traffic
            )
        }
    }
}
